//
//  MeetingAssistantUITests.swift
//  MeetingAssistantUITests
//
//  冒烟测试：核心页面能打开、能关闭、不崩溃。
//

import XCTest

final class MeetingAssistantUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSmokeNavigation() throws {
        let app = XCUIApplication()
        app.launch()

        // 设置页开合
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons["doneButton"].tap()

        // 开始会议 → 实时页出现（模拟器上本地识别模型可能不可用，应显示失败态而非崩溃）
        XCTAssertTrue(app.buttons["startMeetingButton"].waitForExistence(timeout: 5))
        app.buttons["startMeetingButton"].tap()

        // 处理可能弹出的麦克风权限
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons.matching(
            NSPredicate(format: "label IN {'Allow', 'OK', '允许', '好'}")).firstMatch
        if allow.waitForExistence(timeout: 3) {
            allow.tap()
        }

        XCTAssertTrue(app.buttons["stopButton"].waitForExistence(timeout: 15))

        // 演示模式脚本：等待转写行出现并被检测为问题（未配置 LLM 时卡片显示「未配置」提示）
        let transcriptLine = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '向量数据库'")).firstMatch
        XCTAssertTrue(transcriptLine.waitForExistence(timeout: 40))
        let unconfiguredHint = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS '未配置 LLM'")).firstMatch
        XCTAssertTrue(unconfiguredHint.waitForExistence(timeout: 20))

        app.buttons["stopButton"].tap()

        // 回到首页
        XCTAssertTrue(app.buttons["startMeetingButton"].waitForExistence(timeout: 10))
    }
}
