//
//  ContentView.swift
//  a-Shell
//
//  Created by Nicolas Holzschuch on 30/06/2019.
//  Copyright © 2019 AsheKube. All rights reserved.
//

import SwiftUI
import SwiftTerm
import WebKit

// SwiftUI extension for fullscreen rendering
public enum ViewBehavior: Int {
    case original
    case ignoreSafeArea
    case fullScreen
}

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

struct Termview : UIViewRepresentable {
    let view: TerminalView
    
    init() {
        view = TerminalView()
    }
    
    func makeUIView(context: Context) -> UIView {
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context)
    {
        
    }
}

struct Webview : UIViewRepresentable {
    typealias WebViewType = WKWebView

    let webView: WKWebView
    var terminalIconName = "pc"

    init() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(iOS 15.4, *) {
            config.preferences.isElementFullscreenEnabled = true
        }
        if #available(iOS 14.5, *) {
            config.preferences.isTextInteractionEnabled = true
        }
        config.preferences.setValue(true as Bool, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true as Bool, forKey: "allowUniversalAccessFromFileURLs")
        // Does not change anything either way (??? !!!)
        config.preferences.setValue(true as Bool, forKey: "shouldAllowUserInstalledFonts")
        config.selectionGranularity = .character; // Could be .dynamic
        // let preferences = WKWebpagePreferences()
        // preferences.allowsContentJavaScript = true
        webView = .init(frame: .zero, configuration: config)
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        webView.allowsBackForwardNavigationGestures = true
        if #available(iOS 15.0, *) {
            webView.keyboardLayoutGuide.topAnchor.constraint(equalTo: webView.bottomAnchor).isActive = true
            // This is necessary to allow the various edge constraints to engage.
            webView.keyboardLayoutGuide.followsUndockedKeyboard = true
        }
        if #available(iOS 17, *) {
            terminalIconName = "apple.terminal"
        }
    }
    
    func makeUIView(context: Context) -> WebViewType {
        return webView
    }

    func updateUIView(_ uiView: WebViewType, context: Context) {
        if (uiView.url != nil) { return } // Already loaded the page
        uiView.isOpaque = false
        if (appVersion != "a-Shell-mini") {
            uiView.load(URLRequest(url: URL(string: "https://localhost:8443/wasm.html")!))
        } else {
            uiView.load(URLRequest(url: URL(string: "https://localhost:8334/wasm.html")!))
        }
    }
}


public var toolbarShouldBeShown = true
public var useSystemToolbar = false
public var showToolbar = true
public var showKeyboardAtStartup = true
// .fullScreen is too much for floating KB + toolbar, ignoreSafeArea seems to work,
// automatic detection causes blank screen when switching back-forth
// Make this a user-defined setup, with "ignoreSafeArea" the default.
public var viewBehavior: ViewBehavior = .ignoreSafeArea
public var latestNotification: String = ""
public var extendBy: CGFloat = 0
public var showWebView = false

struct ContentView: View {
    @State private var keyboardHeight: CGFloat = 0
    @State private var lastKeyboardHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var frameWidth: CGFloat = 0
    @State private var localShowWebView: Bool = true

    let terminalview = Termview()
    let webview = Webview()
    
    // Adapt window size to keyboard height, see:
    // https://stackoverflow.com/questions/56491881/move-textfield-up-when-thekeyboard-has-appeared-by-using-swiftui-ios
    // A publisher that combines all of the relevant keyboard changing notifications and maps them into a `CGFloat` representing the new height of the
    // keyboard rect.
    private let keyboardChangePublisher = NotificationCenter.Publisher(center: .default,
                                                                       name: UIResponder.keyboardWillShowNotification)
        .merge(with: NotificationCenter.Publisher(center: .default,
                                                  name: UIResponder.keyboardWillChangeFrameNotification))
        .merge(with: NotificationCenter.Publisher(center: .default, name: UIResponder.keyboardWillHideNotification))
    // Now map the merged notification stream into a height value.
        .map { (note) -> CGFloat in
            let height = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).size.height
            let width = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).size.width
            let x = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).origin.x
            let y = (note.userInfo?[UIWindow.keyboardFrameEndUserInfoKey] as? CGRect ?? .zero).origin.y
            let userInfo = note.userInfo
            NSLog("SwiftUI Received \(note.name.rawValue) with height \(height) width \(width) origin: \(x) -- \(y)")
            if (note.name.rawValue == "UIKeyboardWillShowNotification") {
                latestNotification = "UIKeyboardWillShowNotification"
                showKeyboardAtStartup = true
            } else if (note.name.rawValue == "UIKeyboardWillHideNotification") {
                latestNotification = "UIKeyboardWillHideNotification"
            } else {
                latestNotification = ""
            }
            return height
        }
    
    // tests: 1) iPhone vertical, move to horizontal, check that window remains good
    //        2) reverse: iPhone horizontal, move to vertical
    //        3) remove bluetooth connection, check that window is resized after onScreen keyboard appears
    //        4) use hideKeyboard, check that window now extends all the way to the bottom
    //        5) click on screen, check that the bottom of the window is at the top of the toolbar
    var body: some View {
        GeometryReader {geometry in
            Group {
                if (showWebView && localShowWebView) {
                    // NavigationView is deprecated, but the replacement only works for iOS 16 and above.
                    // I'm trying to keep a-Shell active for iOS 14 and above.
                    NavigationView {
                        webview
                            .toolbar {
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: {
                                        NSLog("goBackAction()")
                                        webview.webView.goBack()
                                    }, label: {
                                        Image(systemName: "arrow.backward")
                                    })
                                }
                                ToolbarItem(placement: .navigationBarLeading) {
                                    Button(action: {
                                        NSLog("terminal clicked")
                                        localShowWebView = false
                                        showWebView = false
                                        showKeyboardAtStartup = true
                                        _ = terminalview.view.becomeFirstResponder()
                                        // TODO: restore terminal content, position and scrolling
                                        if (appVersion != "a-Shell-mini") {
                                            webview.webView.load(URLRequest(url: URL(string: "https://localhost:8443/wasm.html")!))
                                        } else {
                                            NSLog("Loding wasm.html from 8334")
                                            webview.webView.load(URLRequest(url: URL(string: "https://localhost:8334/wasm.html")!))
                                        }
                                    }, label: {
                                        Image(systemName: webview.terminalIconName) // apple.terminal or pc depending on the version
                                    })
                                }
                                ToolbarItem(placement: .principal) {
                                    // TODO: it would be great if this could show the title of the web page,
                                    // but I don't know how to do that.
                                    Text("a-Shell navigator")
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button(action: {
                                        NSLog("reload action")
                                        webview.webView.reload()
                                    }, label: {
                                        Image(systemName: "arrow.clockwise.circle")
                                    })
                                }
                                ToolbarItem(placement: .navigationBarTrailing) {
                                    Button(action: {
                                        NSLog("goForward action()")
                                        webview.webView.goForward()
                                    }, label: {
                                        Image(systemName: "arrow.forward")
                                    })
                                }
                            }.navigationBarTitleDisplayMode(.inline)
                    }.navigationViewStyle(.stack) // so the navigation view is full screen on an iPad
                } else {
                    terminalview
                }
            }
            // terminalview
                .onReceive(keyboardChangePublisher) {
                    if (showWebView) {
                        localShowWebView = true
                    }
                    keyboardHeight = $0
                    if !showKeyboardAtStartup || (latestNotification == "UIKeyboardWillHideNotification") {
                        keyboardHeight = 0
                    }
                    frameHeight = geometry.size.height
                    frameWidth = terminalview.view.frame.width
                    if (UIDevice.current.model.hasPrefix("iPhone")) {
                        if (frameWidth > UIScreen.main.bounds.width) {
                            frameWidth = UIScreen.main.bounds.width
                        }
                    } else {
                        if (frameWidth > geometry.size.width) {
                            frameWidth = geometry.size.width
                        }
                    }
                    if (!useSystemToolbar) {
                        // iPhones (mostly) and iPads with not-system toolbars
                        NSLog("Scene: \(UIScreen.main.bounds) terminal frame: \(terminalview.view.frame) geometry: \(geometry.size) keyboardHeight: \(keyboardHeight)")
                        if (UIDevice.current.model.hasPrefix("iPhone")) {
                            // geometry.size.height is wildly all over the place on iPhones
                            frameHeight = UIScreen.main.bounds.height - keyboardHeight
                        } else { // iPads
                            frameHeight = geometry.size.height
                        }
                        if showToolbar && UIDevice.current.model.hasPrefix("iPhone") && (UIScreen.main.bounds.height > UIScreen.main.bounds.width) {
                            // terminalview.view.inputAccessoryView!.bounds says the toolbar has a height of 35, but it's too much
                            // keyboard height takes into account the toolbar height in landscape mode, not in portrait
                            // It's probably a bug that will be fixed at some point
                            frameHeight -= 30
                        }
                    }
                }
            // with useSystemToolbar, it seems to work nicely on the iPad
                .if((viewBehavior == .original || viewBehavior == .ignoreSafeArea) && !useSystemToolbar) {
                    $0.frame(height: frameHeight).position(x: frameWidth / 2, y: frameHeight / 2)
                }
                .if(((viewBehavior == .ignoreSafeArea || viewBehavior == .fullScreen)) && useSystemToolbar) {
                    $0.ignoresSafeArea(.container, edges: .bottom)
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
        }
    }
}
