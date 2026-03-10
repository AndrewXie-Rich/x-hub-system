function isAsciiWhitespace(code) {
  return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d || code === 0x0c || code === 0x0b;
}

function isAsciiWord(code) {
  return (
    (code >= 0x30 && code <= 0x39) ||
    (code >= 0x41 && code <= 0x5a) ||
    (code >= 0x61 && code <= 0x7a) ||
    code === 0x5f ||
    code === 0x2d
  );
}

function toLowerAsciiCode(code) {
  if (code >= 0x41 && code <= 0x5a) return code + 0x20;
  return code;
}

function startsWithPrivateKeyword(input, pos) {
  const word = 'private';
  if (pos + word.length > input.length) return false;
  for (let i = 0; i < word.length; i += 1) {
    const c = input.charCodeAt(pos + i);
    if (toLowerAsciiCode(c) !== word.charCodeAt(i)) return false;
  }
  return true;
}

function parsePrivateTagAt(input, start) {
  if (input.charCodeAt(start) !== 0x3c /* < */) return null;
  const n = input.length;
  let i = start + 1;

  while (i < n && isAsciiWhitespace(input.charCodeAt(i))) i += 1;
  if (i >= n) return null;

  let kind = 'open';
  if (input.charCodeAt(i) === 0x2f /* / */) {
    kind = 'close';
    i += 1;
    while (i < n && isAsciiWhitespace(input.charCodeAt(i))) i += 1;
  }

  if (!startsWithPrivateKeyword(input, i)) return null;
  i += 'private'.length;

  if (i < n) {
    const next = input.charCodeAt(i);
    const boundary = next === 0x3e /* > */ || next === 0x2f /* / */ || isAsciiWhitespace(next);
    // Avoid false-positive on tags like <privately>.
    if (!boundary && isAsciiWord(next)) return null;
  }

  let malformed = false;
  let sawGt = false;
  let tailHasNonWs = false;
  while (i < n) {
    const c = input.charCodeAt(i);
    if (c === 0x3e /* > */) {
      sawGt = true;
      i += 1;
      break;
    }
    if (c === 0x3c /* < */) malformed = true;
    if (!isAsciiWhitespace(c)) tailHasNonWs = true;
    i += 1;
  }

  if (!sawGt) malformed = true;
  if (tailHasNonWs) malformed = true;

  return { kind, end: sawGt ? i : n, malformed };
}

// Strip/redact <private> blocks using a single-pass state machine.
// Fail-closed policy: malformed/nested/unterminated private tags are treated as private.
export function stripPrivateTagsFailClosed(rawText, options = {}) {
  const placeholder = String(options?.placeholder || '[PRIVATE]');
  const input = String(rawText ?? '');
  if (!input) {
    return { text: '', had_private: false, malformed: false, redacted_count: 0 };
  }

  const out = [];
  let chunkStart = 0;
  let i = 0;
  let depth = 0;
  let hadPrivate = false;
  let malformed = false;
  let redactedCount = 0;

  while (i < input.length) {
    if (input.charCodeAt(i) !== 0x3c /* < */) {
      i += 1;
      continue;
    }

    const token = parsePrivateTagAt(input, i);
    if (!token) {
      i += 1;
      continue;
    }

    hadPrivate = true;
    if (token.malformed) malformed = true;

    if (depth === 0 && i > chunkStart) {
      out.push(input.slice(chunkStart, i));
    }

    if (token.kind === 'open') {
      if (depth > 0) malformed = true;
      depth += 1;
      if (depth === 1) redactedCount += 1;
    } else if (depth === 0) {
      malformed = true;
      redactedCount += 1;
      out.push(placeholder);
    } else {
      depth -= 1;
      if (depth === 0) out.push(placeholder);
    }

    i = token.end;
    chunkStart = i;
  }

  if (depth === 0) {
    if (chunkStart < input.length) out.push(input.slice(chunkStart));
  } else {
    malformed = true;
    out.push(placeholder);
  }

  return {
    text: out.join(''),
    had_private: hadPrivate,
    malformed,
    redacted_count: redactedCount,
  };
}
