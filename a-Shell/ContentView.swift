//
//  ContentView.swift
//  a-Shell
//
//  Created by Nicolas Holzschuch on 30/06/2019.
//  Copyright © 2019 AsheKube. All rights reserved.
//

import SwiftUI
import SwiftTerm

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


public var toolbarShouldBeShown = true
public var useSystemToolbar = false
public var showToolbar = true
public var showKeyboardAtStartup = true
// .fullScreen is too much for floating KB + toolbar, ignoreSafeArea seems to work,
// automatic detection causes blank screen when switching back-forth
// Make this a user-defined setup, with "ignoreSafeArea" the default.
public var viewBehavior: ViewBehavior = .ignoreSafeArea

struct ContentView: View {
    @State private var keyboardHeight: CGFloat = 0
    @State private var frameHeight: CGFloat = 0
    @State private var frameWidth: CGFloat = 0

    let terminalview = Termview()
    
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
            // NSLog("SwiftUI Received \(note.name.rawValue) with height \(height) width \(width) origin: \(x) -- \(y)")
            return height
        }
    
    var body: some View {
        GeometryReader {geometry in
            // resize depending on keyboard. Specify size (.frame) instead of padding.
            terminalview
                .onReceive(keyboardChangePublisher) {
                    keyboardHeight = $0
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
                        NSLog("Scene: \(UIScreen.main.bounds) terminal frame: \(terminalview.view.frame) geometry: \(geometry.size)")
                        if (UIDevice.current.model.hasPrefix("iPhone")) {
                            // geometry.size.height is wildly over the place on iPhones
                            frameHeight = UIScreen.main.bounds.height - keyboardHeight;
                        } else { // iPads
                            frameHeight = geometry.size.height - keyboardHeight;
                        }
                        if showToolbar && UIDevice.current.model.hasPrefix("iPhone") && (UIScreen.main.bounds.height > UIScreen.main.bounds.width) {
                            // terminalview.view.inputAccessoryView!.bounds says the toolbar has a height of 35, but it's too much
                            // keyboard height takes into account the toolbar height in landscape mode, not in portrait
                            // It's probably a bug that will be fixed at some point
                            frameHeight -= 30
                        }
                    } else {
                        // iPads with system toolbar
                        frameHeight = geometry.size.height - keyboardHeight;
                    }
                }
                .if(viewBehavior == .original || viewBehavior == .ignoreSafeArea) {
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
