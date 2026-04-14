import Testing
@testable import XTerminal

struct XTLocalizationTests {
    @Test
    func interfaceLanguageDefaultsStayChineseFirst() {
        #expect(XTInterfaceLanguage.defaultPreference == .simplifiedChinese)
        #expect(XTL10n.InterfaceLanguage.title.resolve(.simplifiedChinese) == "界面语言")
        #expect(XTL10n.Common.updated.resolve(.simplifiedChinese) == "已更新")
    }

    @Test
    func interfaceLanguageNamesAndCoreLabelsResolveInEnglish() {
        #expect(XTInterfaceLanguage.simplifiedChinese.displayName(in: .english) == "Simplified Chinese")
        #expect(XTInterfaceLanguage.english.displayName(in: .english) == "English")
        #expect(XTL10n.InterfaceLanguage.title.resolve(.english) == "Interface Language")
        #expect(XTL10n.RouteDiagnose.modelSettingsButton.resolve(.english) == "Supervisor · AI Models")
    }

    @Test
    func menuBarLanguageMenuUsesFixedBilingualTitleAndCheckedNativeOptionNames() {
        #expect(XTL10n.MenuBarLanguage.menuTitle == "语言 / Language")
        #expect(
            XTL10n.MenuBarLanguage.optionTitle(
                .simplifiedChinese,
                selectedLanguage: .simplifiedChinese
            ) == "✓ 简体中文"
        )
        #expect(
            XTL10n.MenuBarLanguage.optionTitle(
                .english,
                selectedLanguage: .simplifiedChinese
            ) == "English"
        )
        #expect(
            XTL10n.MenuBarLanguage.optionTitle(
                .english,
                selectedLanguage: .english
            ) == "✓ English"
        )
    }
}
