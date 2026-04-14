function safeString(input) {
  return String(input ?? '').trim();
}

function safeInt(input, fallback = 0) {
  const n = Number(input);
  return Number.isFinite(n) ? Math.max(0, Math.trunc(n)) : fallback;
}

function safeArray(input) {
  return Array.isArray(input) ? input : [];
}

export function parseOperatorChannelHeartbeatGovernanceSnapshot(input) {
  if (input && typeof input === 'object' && !Array.isArray(input)) return input;
  const raw = safeString(input);
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

export function buildOperatorChannelHeartbeatGovernanceSummaryLines(input) {
  const snapshot = parseOperatorChannelHeartbeatGovernanceSnapshot(input);
  if (!Object.keys(snapshot).length) return [];

  const lines = [];
  const statusDigest = safeString(snapshot.status_digest);
  const quality = safeString(snapshot.latest_quality_band);
  const anomalies = safeArray(snapshot.open_anomaly_types).map((item) => safeString(item)).filter(Boolean);
  const nextReview = snapshot.next_review_due && typeof snapshot.next_review_due === 'object'
    ? snapshot.next_review_due
    : {};
  const nextReviewKind = safeString(nextReview.kind);
  const nextReviewDue = nextReview.due === true ? 'yes' : (nextReview.due === false ? 'no' : '');
  const nextReviewDueAtMs = safeInt(nextReview.due_at_ms, 0);

  if (statusDigest) {
    lines.push(`Review digest: ${statusDigest}`);
  }
  if (quality || anomalies.length) {
    lines.push(
      `Review pressure: quality=${quality || 'unknown'}${anomalies.length ? ` anomalies=${anomalies.join(',')}` : ''}`
    );
  }
  if (nextReviewKind || nextReviewDue || nextReviewDueAtMs > 0) {
    lines.push(
      `Next review: ${nextReviewKind || 'unknown'}${nextReviewDue ? ` due=${nextReviewDue}` : ''}${nextReviewDueAtMs > 0 ? ` at_ms=${nextReviewDueAtMs}` : ''}`
    );
  }

  return lines;
}
