//
//  localWebServerMini.swift
//  localWebServer
//
//  Created by Nicolas Holzschuch on 12/10/2025.
//  Copyright © 2025 AsheKube. All rights reserved.
//

import Foundation
import ExtensionFoundation
import Kitura // for our local server for WebAssembly
import KituraNet
import NIOSSL // for TLS (https) authentification
struct Message: Identifiable, Codable {
    var id: String
    // Add properties that represent data your app sends to its extension.
    var message: String
    struct Response: Codable {
        let returnText: String
    }
}
@objc(MessageProtocol)
protocol MessageProtocol {
    @objc func send(id: String, message: String)
}
let localServerQueue = DispatchQueue(label: "localServer", qos: .userInteractive) // high priority, but not blocking

// Due to Indentifier conventions, if this ever works, it will have to be a different source code for a-Shell and a-Shell mini.
var AppDir = ""
var LibraryDir = ""
var localMessage = Message(id: "local", message: "")
var timer = Timer()

var localServerApp = Router()

/// The AppExtensionConfiguration that will be provided by this extension.
/// This is typically defined by the extension host in a framework.
struct localWebServerConfiguration<E:localWebServerExtension>: AppExtensionConfiguration {
    
    let appExtension: E
    
    init(_ appExtension: E) {
        NSLog("localWebServer: init configuration called")
        self.appExtension = appExtension
    }
    
    /// Determine whether to accept the XPC connection from the host.
    func accept(connection: NSXPCConnection) -> Bool {
        NSLog("localWebServer: received connection request. connection= \(connection)")
        return true
    }
}

/// The AppExtension protocol to which this extension will conform.
/// This is typically defined by the extension host in a framework.
protocol localWebServerExtension : AppExtension { }

extension localWebServerExtension {
    var configuration: some AppExtensionConfiguration {
        // Return your extension's configuration upon request.
        return ConnectionHandler(onSessionRequest: { request in
            let handler = MessageHandler(appExtension: self)
            return request.accept { session in
                return handler
            }
        })
    }
}
 
fileprivate struct MessageHandler<E: localWebServerExtension>: XPCPeerHandler, Sendable {
    let appExtension: E
     
    func handleIncomingRequest(_ message: Message) -> (any Encodable)? {
        // Process the incoming message.
        // The messages do arrive and are treated, I'm not sure about the replies
        if (message.id == "APPDIR") {
            AppDir = message.message
            if (AppDir.last != "/") {
                AppDir += "/"
            }
        } else if (message.id == "LibraryDir") {
            LibraryDir = message.message
            if (LibraryDir.last != "/") {
                LibraryDir += "/"
            }
        } else if (message.id == "run") {
            Kitura.run() // That doesn't work either
        }
        return Message.Response(returnText: "OK")
    }
}


@main
class localWebServer: localWebServerExtension {
    required init() {
        // Extension can write to file, but DocumentsDir is *not* the same as the app dir.
        // The best solution for debugging is to call the XPC connection, but I cannot make it work.
        // Bundle.main.resourcePath ==  /private/var/containers/Bundle/Application/<UUID>/a-Shell-mini.app/Extensions/localWebServerMini.appex\
        AppDir = Bundle.main.resourcePath!
        AppDir.removeLast("Extensions/localWebServer.appex".count)
        
        localServerApp.get("/*") { request, response, next in
            NSLog("Kitura request received: \(request.matchedPath)")
            // Load ~/Library/node_modules first if it exists:
            // This also loads ~/Library/wasm.html and ~/Library/require.js if the user really wants to.
            // Must also check libraryURL! (send it via XPC connection?)
            let localFilePath = LibraryDir + request.matchedPath
            let rootFilePath = AppDir + request.matchedPath
            var fileName: String? = nil
            NSLog("Kitura file requested: \(request.matchedPath). Trying \(localFilePath)  and \(rootFilePath)")
            if (FileManager().fileExists(atPath: localFilePath) && !URL(fileURLWithPath: localFilePath).isDirectory) {
                fileName = localFilePath
            } else if (FileManager().fileExists(atPath: rootFilePath) && !URL(fileURLWithPath: rootFilePath).isDirectory) {
                fileName = rootFilePath
            }
            if let filePath = fileName {
                if (request.matchedPath.hasSuffix(".html")) {
                    response.headers["Content-Type"] = "text/html"
                } else if (request.matchedPath.hasSuffix(".js")) {
                    response.headers["Content-Type"] = "application/javascript"
                } else if (request.matchedPath.hasSuffix(".wasm")) {
                    response.headers["Content-Type"] = "application/wasm"
                }
                // These headers get us a "crossOriginIsolated == true;" on OSX Safari
                response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
                response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
                response.headers["Cross-Origin-Resource-Policy"] =  "same-origin"
                do {
                    NSLog("Kitura file found: \(filePath)")
                    try response.send(fileName: filePath)
                }
                catch {
                    response.statusCode = .forbidden
                    response.send("Loading \(filePath) failed")
                }
            } else {
                NSLog("Kitura file not found: \(request.matchedPath)")
                response.statusCode = .notFound
                response.send("")
            }
            next()
        }
        NSLog("Starting Kitura.")
        let sslConfig =  SSLConfig(withChainFilePath: Bundle.main.resourcePath! + "/localCertificate.pfx",
                                   withPassword: "password",
                                   usingSelfSignedCerts: true)
        // a-Shell mini port:
        Kitura.addHTTPServer(onPort: 8334, with: localServerApp, withSSL: sslConfig)
        /*
         localServerQueue.async{
            // The catch here is:
            // - start Kitura in the main loop: it gets killed after 5 seconds
            // - start Kitura in a local Queue: it never gets started
            Kitura.run()
            NSLog("Ended Kitura.")
        } */
    }

    @AppExtensionPoint.Bind
    var boundExtensionPoint: AppExtensionPoint {
        AppExtensionPoint.Identifier(host: "AsheKube.app.a-Shell-mini", name: "localWebServer")
    }
}


