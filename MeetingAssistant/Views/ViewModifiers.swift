//
//  ViewModifiers.swift
//  MeetingAssistant
//
//  跨设备布局辅助。
//

import SwiftUI

extension View {
    /// 大屏上限制正文宽度并居中：行长过长会明显影响阅读（iPad 全宽可达 1200pt+）。
    /// iPhone 上宽度不足 maxWidth，等同于无效果。
    func readableWidth(_ maxWidth: CGFloat = 760) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}
