import SwiftUI
import RELFlowHubCore

extension SettingsSheetView {
    @ViewBuilder
    var modelResourcePoolsSection: some View {
        let pools = modelResourcePools
        Section("资源池总览") {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        modelResourcePoolsHeadline(pools)
                        Spacer(minLength: 12)
                        modelResourcePoolsHeaderControls(pools)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        modelResourcePoolsHeadline(pools)
                        modelResourcePoolsHeaderControls(pools)
                    }
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 320), spacing: 12, alignment: .top)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(pools) { pool in
                        modelResourcePoolCard(pool)
                    }
                }

                Text("第一屏只回答“哪个池子能用、还剩多少、能跑哪些模型”。账号、消费者、物理 key 和配额链路放在下面的高级配额运营里。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
