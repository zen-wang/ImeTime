import SwiftUI

/// 設定讀取失敗時的替代畫面。只在開發設定不完整時出現，所以講清楚不是使用者帳號的問題。
struct ConfigurationErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "gearshape.badge.xmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("設定不完整")
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("這是開發設定問題，與你的帳號無關。")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(24)
    }
}

#Preview {
    ConfigurationErrorView(message: AppConfigError.missingAnonKey.userMessage)
}
