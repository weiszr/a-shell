//
//  SceneDelegate+TerminalView.swift
//  a-Shell
//
//  Created by Nicolas Holzschuch on 24/12/2025.
//  Copyright © 2025 AsheKube. All rights reserved.
//
import SwiftTerm // for the terminal window
import ios_system
import TipKit // for helpful tips

var autocompleteRunning = false
var autocompleteSuggestions: [String] = []
var autocompletePosition = 0
var autocompleteOptions = false
// variables for user interaction with SwiftTerm:
var commandBeforeCursor = ""
var commandAfterCursor = ""

extension SceneDelegate {
    
    func longestCommonPrefix(_ strs: [String]) -> String {
        guard let first = strs.first else { return "" }
        
        var prefix = first
        
        for str in strs {
            while !str.hasPrefix(prefix) {
                prefix = String(prefix.dropLast())
                if prefix.isEmpty { return "" }
            }
        }
        
        return prefix
    }
    
    func fillAutocompleteSuggestions(command: String) {
        autocompleteSuggestions = []
        autocompletePosition = 0
        autocompleteOptions = false
        if (currentCommand != "") {
            // a command is running, suggestions are only from command history
            for suggestion in commandHistory {
                if suggestion.hasPrefix(command) {
                    var shortenedSugg = suggestion
                    shortenedSugg.removeFirst(command.count)
                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                        autocompleteSuggestions.append(shortenedSugg)
                    }
                }
            }
            // the last command entered is the suggestion:
            autocompletePosition = autocompleteSuggestions.count - 1
        } else {
            // no commands are running:
            // suggestions are history + available commands
            for suggestion in history.reversed() { // reversed so the latest command appears first
                if suggestion.hasPrefix(command) {
                    var shortenedSugg = suggestion
                    shortenedSugg.removeFirst(command.count)
                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                        autocompleteSuggestions.append(shortenedSugg)
                    }
                }
            }
            // TODO: if there is a pipe (|) in the command, split on the last one, then redo this.

            // Are we autocompleting a command or something else?
            // TODO: this creates problems for "\ " and quoted spaces. We just need first and last components.
            var commandParts = command.components(separatedBy: " ")
            NSLog("commandParts: \(commandParts)")
            if (commandParts.count == 1) {
                // Autocompleting a command:
                // The aliases go first:
                let aliasArray = aliasesAsArray() as! [String]?
                for suggestion in aliasArray! { // alphabetical order
                    if suggestion.hasPrefix(command) {
                        var shortenedSugg = suggestion
                        shortenedSugg.removeFirst(command.count)
                        if (!autocompleteSuggestions.contains(shortenedSugg)) {
                            autocompleteSuggestions.append(shortenedSugg)
                        }
                    }
                }
                // Followed by the actual commands:
                for suggestion in commandsArray { // alphabetical order
                    if suggestion.hasPrefix(command) {
                        var shortenedSugg = suggestion
                        shortenedSugg.removeFirst(command.count)
                        if (!autocompleteSuggestions.contains(shortenedSugg)) {
                            autocompleteSuggestions.append(shortenedSugg)
                        }
                    }
                }
            } else {
                // We have already entered a command:
                let futureCommand = aliasedCommand(commandParts.first)
                let commandOperatesOn = operatesOn(futureCommand)
                let optionList = getoptString(futureCommand)
                let lastElement = commandParts.last
                var directoryForListing = lastElement
                if (lastElement?.first == "-") {
                    // options, like "-l"
                    if (optionList != nil) {
                        for i in 0..<optionList!.count {
                            var option = String(optionList![optionList!.index(optionList!.startIndex, offsetBy: i)])
                            if (option != ":") {
                                if (i < optionList!.count - 1) {
                                    // if an option is followed by ":", then it expects an argument, so we add a space:
                                    let nextChar = optionList![optionList!.index(optionList!.startIndex, offsetBy: i + 1)]
                                    if (nextChar == ":") {
                                        option = option + " "
                                    }
                                }
                                if (!lastElement!.contains(option)) && (!command.contains("-" + String(option))) {
                                    autocompleteOptions = true
                                    autocompleteSuggestions.append(String(option))
                                }
                            }
                        }
                    }
                } else if (lastElement?.first == "$") {
                    // environment variable
                    if (lastElement!.contains("/")) {
                        let directoryComponents = lastElement!.split(separator: "/", maxSplits: 1)
                        var environmentVariable = String(directoryComponents[0])
                        environmentVariable.removeFirst()
                        if directoryComponents.count == 1 {
                            if environmentVariable.hasSuffix("/") {
                                environmentVariable.removeLast()
                            }
                            directoryForListing = String(cString: ios_getenv(environmentVariable)) + "/"
                        } else {
                            directoryForListing = String(cString: ios_getenv(environmentVariable)) + "/" + String(directoryComponents[1])
                        }
                    } else {
                        let environmentVariables = environmentAsArray()
                        for envVar in environmentVariables! {
                            if let envVarString = envVar as? String {
                                let variableName = "$" + envVarString
                                if variableName.hasPrefix(lastElement!) {
                                    let envVarParts = envVarString.split(separator: "=", maxSplits: 1)
                                    var shortenedSugg = String(envVarParts[0])
                                    var pointsToDirectory = false
                                    if (envVarParts.count > 0) {
                                        if URL(fileURLWithPath: String(envVarParts[1])).isDirectory {
                                            pointsToDirectory = true
                                        }
                                    }
                                    if (commandOperatesOn == "directory") && !pointsToDirectory {
                                        continue
                                    }
                                    if ((commandOperatesOn == "file") || (commandOperatesOn == "directory")) &&
                                        (envVarParts.count > 0) && pointsToDirectory {
                                        shortenedSugg += "/"
                                    }
                                    shortenedSugg.removeFirst(lastElement!.count - 1)
                                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                                        autocompleteSuggestions.append(shortenedSugg)
                                    }
                                }
                            }
                        }
                    }
                } else if (lastElement?.first == "~") {
                    let storedNamesDictionary = UserDefaults.standard.dictionary(forKey: "bookmarkNames") ?? [:]
                    if (lastElement!.contains("/")) {
                        let directoryComponents = lastElement!.split(separator: "/", maxSplits: 1)
                        var bookmarkName = String(directoryComponents[0])
                        bookmarkName.removeFirst()
                        if directoryComponents.count == 1 {
                            if (bookmarkName.hasSuffix("/")) {
                                bookmarkName.removeLast()
                            }
                            if let path = storedNamesDictionary[bookmarkName] as? String {
                                directoryForListing = path + "/"
                            } else {
                                NSLog("Unable to extract path for \(bookmarkName)")
                            }
                        } else {
                            let urlPath = storedNamesDictionary[bookmarkName]
                            let path = (urlPath as! String)
                            directoryForListing = path + "/" + String(directoryComponents[1])
                        }
                    } else {
                        var sortedKeys = storedNamesDictionary.keys.sorted() // alphabetical order
                        if (commandOperatesOn == "directory") {
                            // sort directories in order of use:
                            sortedKeys = sortedKeys.sorted(by: { current, next in rankDirectory(dir:"~" + current, base: nil) > rankDirectory(dir:"~" + next, base: nil)})
                        }
                        for key in sortedKeys {
                            var pointsToDirectory = false
                            if let path = storedNamesDictionary[key] as? String {
                                if (URL(fileURLWithPath: path).isDirectory) {
                                    pointsToDirectory = true
                                }
                            }
                            if (commandOperatesOn == "directory") && !pointsToDirectory {
                                continue
                            }
                            var bookmarkName = "~" + key
                            if bookmarkName.hasPrefix(lastElement!) {
                                if ((commandOperatesOn == "file") || (commandOperatesOn == "directory")) && pointsToDirectory {
                                    bookmarkName += "/"
                                }
                                bookmarkName.removeFirst(lastElement!.count)
                                bookmarkName = bookmarkName.replacingOccurrences(of: " ", with: "\\ ")
                                if (!autocompleteSuggestions.contains(bookmarkName)) {
                                    autocompleteSuggestions.append(bookmarkName)
                                }
                            }
                        }
                    }
                }
                if (!autocompleteOptions) {
                    // add the content of the directory in directoryForListing
                    var prefix = ""
                    if let directoryForListing = directoryForListing {
                        var directory = directoryForListing
                        if (directoryForListing == "") {
                            directory = "."
                        }
                        var matchingPath = URL(fileURLWithPath: directoryForListing).lastPathComponent
                        if URL(fileURLWithPath: directoryForListing).isDirectory {
                            matchingPath = ""
                            if !directory.hasSuffix("/") && (directoryForListing != "") {
                                prefix = "/"
                            }
                        } else {
                            directory.removeLast(matchingPath.count)
                            if (directory == "") {
                                directory = "."
                            }
                        }
                        do {
                            var filePaths = try FileManager().contentsOfDirectory(atPath: directory)
                            filePaths.sort() // alphabetical order
                            if (commandOperatesOn == "directory") {
                                // sort directories in order of use:
                                var directoryForSorting = directory
                                if (directoryForSorting == ".") {
                                    if (directoryForSorting == ".") {
                                        directoryForSorting = FileManager().currentDirectoryPath
                                    } else if (directoryForSorting.hasPrefix("./")) {
                                        directoryForSorting = directoryForSorting.replacingOccurrences(of: "./", with: FileManager().currentDirectoryPath + "/")
                                    } else {
                                        directoryForSorting = FileManager().currentDirectoryPath + "/" + directoryForSorting
                                    }
                                }
                                let localDirCompact = String(cString: ios_getBookmarkedVersion(directoryForSorting.utf8CString))
                                filePaths = filePaths.sorted(by: { current, next in rankDirectory(dir:current, base: localDirCompact) > rankDirectory(dir:next, base: localDirCompact)})
                                // NSLog("after sorting: \(filePaths)")
                            }
                            // Add all non hidden-files first, then all hidden files:
                            for filePath in filePaths {
                                let fullPath = directory + "/" + filePath
                                // NSLog("path = \(fullPath) , isDirectory: \(URL(fileURLWithPath: fullPath).isDirectory)")
                                let isDirectory = URL(fileURLWithPath: fullPath).isDirectory
                                if (commandOperatesOn == "directory") && !isDirectory {
                                    continue
                                }
                                var filePath = fullPath
                                if (isDirectory) {
                                    filePath += "/"
                                }
                                filePath.removeFirst(directory.count + 1)
                                if filePath.hasPrefix(".") {
                                    continue
                                }
                                NSLog("Checking \(filePath) against \"\(matchingPath)\": \(filePath.hasPrefix(matchingPath))")
                                if (matchingPath == "") {
                                    filePath = prefix + filePath
                                    filePath = filePath.replacingOccurrences(of: " ", with: "\\ ")
                                    if (!autocompleteSuggestions.contains(filePath)) {
                                        autocompleteSuggestions.append(filePath)
                                    }
                                } else if filePath.hasPrefix(matchingPath) {
                                    var shortenedSugg = filePath
                                    shortenedSugg.removeFirst(matchingPath.count)
                                    shortenedSugg = shortenedSugg.replacingOccurrences(of: " ", with: "\\ ")
                                    NSLog("Adding \"\(shortenedSugg)\"")
                                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                                        autocompleteSuggestions.append(shortenedSugg)
                                    }
                                }
                            }
                            for filePath in filePaths {
                                let fullPath = directory + "/" + filePath
                                // NSLog("path = \(fullPath) , isDirectory: \(URL(fileURLWithPath: fullPath).isDirectory)")
                                let isDirectory = URL(fileURLWithPath: fullPath).isDirectory
                                if (commandOperatesOn == "directory") && !isDirectory {
                                    continue
                                }
                                var filePath = fullPath
                                if (isDirectory) {
                                    filePath += "/"
                                }
                                filePath.removeFirst(directory.count + 1)
                                if !filePath.hasPrefix(".") {
                                    continue
                                }
                                if (matchingPath == "") {
                                    filePath = prefix + filePath
                                    filePath = filePath.replacingOccurrences(of: " ", with: "\\ ")
                                    if (!autocompleteSuggestions.contains(filePath)) {
                                        autocompleteSuggestions.append(filePath)
                                    }
                                } else if filePath.hasPrefix(matchingPath) {
                                    var shortenedSugg = filePath
                                    shortenedSugg.removeFirst(matchingPath.count)
                                    shortenedSugg = shortenedSugg.replacingOccurrences(of: " ", with: "\\ ")
                                    if (!autocompleteSuggestions.contains(shortenedSugg)) {
                                        autocompleteSuggestions.append(shortenedSugg)
                                    }
                                }
                            }
                        }
                        catch {
                            NSLog("unable to list files in \(directory): \(error)")
                        }
                    }
                    
                }
            }
        }
    }
    
    // prints a string for autocomplete and move the rest of the command around, even if it is over multiple lines.
    // keep the command as it is until autocomplete has been accepted.
    func printAutocompleteString(suggestion: String) {
        // clear entire buffer, then reprint
        terminalView?.feed(text: escape + "[0J"); // delete display after cursor
        terminalView?.clearToEndOfLine()
        if (terminalView!.tintColor.getBrightness() > terminalView!.backgroundColor!.getBrightness()) {
            // We are in dark mode. Use yellow font for higher contrast
            terminalView?.feed(text: escape + "[33m")  // yellow
        } else {
            // light mode
            terminalView?.feed(text: escape + "[32m")  // yellow
            
        }
        terminalView?.feed(text: suggestion)
        terminalView?.feed(text: escape + "[39m")  // back to normal foreground color
    }
    
    func updateAutocomplete(text: String) {
        // remove all suggestions that don't fit the new string
        let currentSuggestion = autocompleteSuggestions[autocompletePosition]
        if (!autocompleteOptions) {
            autocompleteSuggestions.removeAll(where: { !$0.hasPrefix(text) })
        } else {
            // - remove suggestions that are not options and don't match
            // - keep suggestions that are not options and match (but shorten them)
            // - if there is a suggestion that is an option, and matches, and expects and argument, remove all other options but keep history
            // - (options will be approximated as "suggestions that are one letter or one letter + space)
            // if there are suggestions from history that fit the new case, keep them and keep autocomplete
            var optionExpectsArgument = false
            for s in autocompleteSuggestions {
                if s == text + " " {
                    optionExpectsArgument = true
                    break
                }
            }
            var optionMatch = text
            if (optionExpectsArgument) {
                optionMatch += " "
            }
            autocompleteSuggestions.removeAll(where: { $0 == optionMatch })
            if (optionExpectsArgument) {
                autocompleteSuggestions.removeAll(where: { !$0.hasPrefix(optionMatch) })
                commandBeforeCursor += " "
                terminalView?.feed(text: " ")
                autocompleteOptions = false
                if (autocompleteSuggestions.count < 1) {
                    autocompleteRunning = false
                } else {
                    autocompletePosition = 0
                    for i in 0..<autocompleteSuggestions.count {
                        var shortenedSugg = autocompleteSuggestions[i]
                        if (shortenedSugg == currentSuggestion) {
                            autocompletePosition = i
                        }
                        shortenedSugg.removeFirst(optionMatch.count)
                        autocompleteSuggestions[i] = shortenedSugg
                    }
                }
                return
            } else {
                autocompleteSuggestions.removeAll(where: { !$0.hasPrefix(optionMatch) && (
                    ($0.count > 1) &&
                    !(($0.count == 2) && ($0.hasSuffix(" ")))
                )})
            }
        }
        switch (autocompleteSuggestions.count) {
        case 0:
            stopAutocomplete()
        case 1:
            // erase everything
            terminalView?.feed(text: escape + "[0J"); // delete display after cursor
            terminalView?.clearToEndOfLine()
            var suggestion = autocompleteSuggestions[0]
            suggestion.removeFirst(text.count)
            commandBeforeCursor += suggestion
            terminalView?.feed(text: suggestion)
            terminalView?.saveCursorPosition()
            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
            terminalView?.restoreCursorPosition()
            autocompleteRunning = false
        default:
            autocompletePosition = min (autocompletePosition, autocompleteSuggestions.count - 1)
            for i in 0..<autocompleteSuggestions.count {
                var shortenedSugg = autocompleteSuggestions[i]
                if (shortenedSugg == currentSuggestion) {
                    autocompletePosition = i
                }
                // Shorten all suggestions that are not an option
                if !autocompleteOptions || !((shortenedSugg.count == 1) || ((shortenedSugg.count == 2) && shortenedSugg.hasSuffix(" "))) {
                    shortenedSugg.removeFirst(text.count)
                    autocompleteSuggestions[i] = shortenedSugg
                }
            }
            let prefix = longestCommonPrefix(autocompleteSuggestions)
            for i in 0..<autocompleteSuggestions.count {
                var shortenedSugg = autocompleteSuggestions[i]
                shortenedSugg.removeFirst(prefix.count)
                autocompleteSuggestions[i] = shortenedSugg
            }
            commandBeforeCursor += prefix
            terminalView?.feed(text: prefix) // prints the rest of the line
            terminalView?.saveCursorPosition()
            printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
            terminalView?.restoreCursorPosition()
            autocompleteRunning = true
        }
    }
    
    func stopAutocomplete() {
        autocompleteRunning = false
        autocompleteSuggestions = []
        autocompletePosition = 0
        terminalView?.feed(text: escape + "[0J"); // delete display after cursor
        terminalView?.clearToEndOfLine()
        terminalView?.saveCursorPosition()
        terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
        terminalView?.restoreCursorPosition()
    }
    
    func findNextWord(string: String) -> String {
        let regex = try? NSRegularExpression(pattern: "(\\b)", options: [])
        let results = regex?.matches(in: string, options: [], range: NSRange(string.startIndex..., in: string))
        var returnValue = ""
        var offset = 0
        if let matches = results {
            for match in matches {
                let range = match.range
                let subString = string[string.index(string.startIndex, offsetBy:offset)..<string.index(string.startIndex, offsetBy: range.lowerBound)]
                returnValue += subString
                if (subString != " ") && subString != "/" && subString != "" {
                    return returnValue
                }
                offset = range.upperBound
            }
        }
        // If there's no word boundary, return the entire string:
        return string
    }
    
    private func title(_ button: UIBarButtonItem) -> String? {
        if let possibleTitles = button.possibleTitles {
            for attemptedTitle in possibleTitles {
                if (attemptedTitle.count > 0) {
                    return attemptedTitle
                }
            }
        }
        return button.title
    }
    
    // TerminalViewDelegate stubs:
    func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
        if (newRows != height) || (newCols != width) {
            ios_setWindowSize(Int32(newCols), Int32(newRows), self.persistentIdentifier?.toCString())
        }
        if (newRows != height) {
            height = newRows
            setenv("LINES", "\(height)".toCString(), 1)
        }
        if (newCols != width) {
            width = newCols
            setenv("COLUMNS", "\(width)".toCString(), 1)
        }
    }
    
    // None of these are called.
    func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
        // Nope
    }
    
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {
        NSLog("hostCurrentDirectoryUpdate: \(directory)")
    }
    
    func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
        // This is where I treat the incoming keypress
        if (currentCommand != "") && (commandBeforeCursor == "") && (commandAfterCursor == "") {
            // Sets the position of the end of the prompt for commands inside commands:
            terminalView!.setPromptEnd()
        }
        if var string = String (bytes: data, encoding: .utf8) {
            if (controlOn) {
                // a) switch control off
                controlOn = false
                if #available(iOS 15.0, *) {
                    if (!useSystemToolbar) {
                        for button in editorToolbar.items! {
                            if title(button) == "control" {
                                button.isSelected = controlOn
                                break
                            }
                        }
                    } else {
                        var foundControl = false
                        if let leftButtonGroups = terminalView?.inputAssistantItem.leadingBarButtonGroups {
                            for leftButtonGroup in leftButtonGroups {
                                for button in leftButtonGroup.barButtonItems {
                                    if title(button) == "control" {
                                        foundControl = true
                                        button.isSelected = controlOn
                                        break
                                    }
                                }
                            }
                        }
                        if (!foundControl) {
                            if let rightButtonGroups = terminalView?.inputAssistantItem.trailingBarButtonGroups {
                                for rightButtonGroup in rightButtonGroups {
                                    for button in rightButtonGroup.barButtonItems {
                                        if title(button) == "control" {
                                            button.isSelected = controlOn
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                // b) extract control code:
                string = string.uppercased()
                switch string {
                    // transform control-arrows into alt-arrows:
                case escape + "OA": // up arrow (application mode)
                    fallthrough
                case escape + "[A": // up arrow
                    string = escape + "[1;3A";  // Alt-Up arrow
                case escape + "OB": // down arrow (application mode)
                    fallthrough
                case escape + "[B": // down arrow
                    string = escape + "[1;3B";  // Alt-Down arrow
                case escape + "OC": // right arrow (application mode)
                    fallthrough
                case escape + "[C": // right arrow
                    string = escape + "[1;3C";  // Alt-right arrow
                case escape + "OD": // left arrow (application mode)
                    fallthrough
                case escape + "[D": // left arrow
                    string = escape + "[1;3D";  // Alt-left arrow
                    break;
                default:
                    // create a control-something character
                    if let controlChar = string.first {
                        if let asciiCode = controlChar.asciiValue {
                            if (asciiCode > 64) {
                                string = String(UnicodeScalar(asciiCode - 64))
                            }
                        }
                    }
                }
            }
            // terminal sending button event:
            var cursorTracking = false
            var cursorTrackingRow = 0
            var cursorTrackingColumn = 0
            if (string.hasPrefix(escape + "[M")) {
                var tracking = string
                tracking.removeFirst((escape + "[M").count)
                cursorTracking = true
                cursorTrackingRow = Int(tracking.last?.asciiValue ?? 32) - 32
                cursorTrackingColumn = Int(tracking[tracking.index(tracking.startIndex, offsetBy: 1)].asciiValue ?? 32) - 32
                // NSLog("tracking: \(button?.asciiValue) \((x.asciiValue)! - 32) \((y?.asciiValue)! - 32)")
            }
            if (currentCommand != "") {
                // If there is an interactive command running, we send the data to its stdin thread
                // active pager (interactive command): gets all the input sent through TTY:
                if (ios_activePager() != 0) {
                    if (tty_file_input != nil) {
                        let savedSession = ios_getContext()
                        ios_switchSession(self.persistentIdentifier?.toCString())
                        ios_setContext(UnsafeMutableRawPointer(mutating: self.persistentIdentifier?.toCString()))
                        ios_setStreams(self.stdin_file, self.stdout_file, self.stdout_file)
                        if let data = string.data(using: .utf8) {
                            tty_file_input?.write(data)
                        }
                        // We can get a session context that is not a valid UUID (InExtension, shSession...)
                        // In that case, don't switch back to it:
                        if let stringPointer = UnsafeMutablePointer<CChar>(OpaquePointer(savedSession)) {
                            let savedSessionIdentifier = String(cString: stringPointer)
                            if let uuid = UUID(uuidString: savedSessionIdentifier) {
                                ios_switchSession(savedSession)
                                ios_setContext(savedSession)
                            }
                        }
                    }
                    return
                }
                // from here on, we can assume ios_activePager() == 0
                // If there is a webAssembly command running:
                if (javascriptRunning && (thread_stdin_copy != nil)) {
                    wasmWebView?.evaluateJavaScript("inputString += '\(string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\n"))'; commandIsRunning;") { (result, error) in
                        // if let error = error { print(error) }
                        if let result = result as? Bool {
                            if (!result) {
                                self.endWebAssemblyCommand(error: 0, message: "")
                            }
                        }
                    }
                    stdinString += string
                    NSLog("input sent to WebAssembly: \(string)")
                    return
                }
                if (!javascriptRunning && executeWebAssemblyCommandsRunning) {
                    // There seems to be cases where the webassembly command did not terminate properly.
                    // We catch it here:
                    wasmWebView?.evaluateJavaScript("commandIsRunning;") { (result, error) in
                        // if let error = error { print(error) }
                        if let result = result as? Bool {
                            if (!result) {
                                self.endWebAssemblyCommand(error: 0, message: "")
                            }
                        }
                    }
                }
                // Special case: help() and license() in ipython are not interactive.
                var helpRunningInIpython = false
                if (currentCommand.hasPrefix("ipython") || currentCommand.hasPrefix("isympy")) {
                    if let lastLine = terminalView?.getLastPrompt() {
                        if (lastLine.hasSuffix("help> ") ||
                            lastLine.hasSuffix("Hit Return for more, or q (and Return) to quit: ") ||
                            lastLine.hasSuffix("Do you really want to exit ([y]/n)? ")) {
                            helpRunningInIpython = true
                        }
                    }
                }
                // interactive command: send the data directly
                if interactiveCommandRunning && !helpRunningInIpython {
                    ios_switchSession(self.persistentIdentifier?.toCString())
                    ios_setContext(UnsafeMutableRawPointer(mutating: self.persistentIdentifier?.toCString()));
                    ios_setStreams(self.stdin_file, self.stdout_file, self.stdout_file)
                    // Interactive commands: just send the input to them. Allows Vim to map control-D to down half a page.
                    guard let data = string.data(using: .utf8) else { return }
                    guard stdin_file_input != nil else { return }
                    // TODO: don't send data if pipe already closed (^D followed by another key)
                    // (store a variable that says the pipe has been closed)
                    // NSLog("Writing (interactive) \(command) to stdin")
                    stdin_file_input?.write(data)
                    return
                }
            }
            // TODO: don't send data if pipe already closed (^D followed by another key)
            // (store a variable that says the pipe has been closed)
            // NSLog("Writing (not interactive) \(command) to stdin")
            // stdin_file_input?.write(data)
            // insert mode does not work, so we keep our own version of the command line.
            if (cursorTracking) {
                if (autocompleteRunning) {
                    stopAutocomplete()
                }
                if let distance = terminalView?.setCursorPosition(x: cursorTrackingColumn - 1, y: cursorTrackingRow - 1) {
                    let command = commandBeforeCursor + commandAfterCursor
                    if (distance <= 0) {
                        // beginning of line
                        commandBeforeCursor = ""
                        commandAfterCursor = command
                    } else {
                        NSLog("command: \(command) distance: \(distance)")
                        var length = 0
                        commandBeforeCursor = ""
                        for c in command {
                            var characterWidth = NSAttributedString(string: String(c), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                length += 2
                                // "large" characters: takes two columns
                            } else {
                                length += 1
                            }
                            NSLog("character: \(c) length: \(length) distance: \(distance)")
                            commandBeforeCursor += String(c)
                            if (length >= distance) {
                                break
                            }
                        }
                        if (command.count > commandBeforeCursor.count) {
                            commandAfterCursor = command
                            commandAfterCursor.removeFirst(commandBeforeCursor.count)
                        }
                        NSLog("\(commandBeforeCursor) -- \(commandAfterCursor)")
                    }
                }
                return
            }
            NSLog("received string: \"\(string)\"")
            // remove the copy-paste-select menu if it is visible:
            if UIMenuController.shared.isMenuVisible {
                UIMenuController.shared.hideMenu()
            }
            switch (string) {
            case endOfTransmission:
                // Stop standard input for the command:
                if (currentCommand != "") {
                    guard stdin_file_input != nil else {
                        // no command running, maybe it ended without us knowing:
                        printPrompt()
                        return
                    }
                    do {
                        try stdin_file_input?.close()
                    }
                    catch {
                        // NSLog("Could not close stdin input.")
                    }
                    stdin_file_input = nil
                }
            case interrupt:
                if autocompleteRunning {
                    stopAutocomplete()
                } else {
                    if (currentCommand != "") && (!javascriptRunning) {
                        // Calling ios_kill while executing webAssembly or JavaScript is a bad idea.
                        // Do we have a way to interrupt JS execution in WkWebView?
                        ios_kill() // TODO: add printPrompt() here if no command running
                    }
                    if (currentCommand == "") {
                        // disable auto-complete menu if running
                        // don't execute command, move to next line, print prompt
                        commandBeforeCursor = ""
                        commandAfterCursor = ""
                        terminalView?.feed(text: "\r\n")
                        printPrompt()
                    }
                }
            case "\u{0008}": // control H - delete
                fallthrough
            case deleteBackward:
                // send arrow-left, then delete-char, but only if there is something to delete:
                if autocompleteRunning {
                    stopAutocomplete()
                } else {
                    if (commandBeforeCursor.count > 0) {
                        terminalView?.moveUpIfNeeded()
                        if let lastChar = commandBeforeCursor.last {
                            NSLog("deleting: \"\(lastChar)\"")
                            commandBeforeCursor.removeLast()
                            let characterWidth = NSAttributedString(string: String(lastChar), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                // "large" characters: delete two columns
                                terminalView?.feed(text: escape + "[D")
                                terminalView?.feed(text: escape + "[P")
                            }
                            terminalView?.feed(text: escape + "[D")
                            terminalView?.feed(text: escape + "[P")
                        }
                    }
                    if (commandAfterCursor.count > 0) {
                        // redraw the end of the line
                        terminalView?.saveCursorPosition()
                        terminalView?.clearToEndOfLine()
                        terminalView?.feed(text: commandAfterCursor)
                        terminalView?.restoreCursorPosition()
                    }
                }
            case tabulation: // autocomplete
                NSLog("received tab. Autocomplete running: \(autocompleteRunning)")
                if (autocompleteRunning) {
                    if (autocompleteOptions) {
                        // insert the option, keep running autocomplete:
                        let string = autocompleteSuggestions[autocompletePosition]
                        commandBeforeCursor += string
                        terminalView?.feed(text: string) // prints the string
                        updateAutocomplete(text: string)
                    } else {
                        commandBeforeCursor += autocompleteSuggestions[autocompletePosition]
                        terminalView?.feed(text: autocompleteSuggestions[autocompletePosition])
                        if (autocompleteSuggestions[autocompletePosition].hasSuffix("/")) {
                            // single suggestion, is a directory: fill again but don't force
                            fillAutocompleteSuggestions(command: commandBeforeCursor)
                            NSLog("suggestions: \(autocompleteSuggestions)")
                            if (autocompleteSuggestions.count > 0) {
                                terminalView?.saveCursorPosition()
                                printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                                terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                                terminalView?.restoreCursorPosition()
                                autocompleteRunning = true
                            } else {
                                autocompleteRunning = false
                            }
                        } else {
                            autocompleteSuggestions = []
                            autocompletePosition = 0
                            autocompleteRunning = false
                        }
                    }
                } else {
                    // standard version, first time we press tab
                    fillAutocompleteSuggestions(command: commandBeforeCursor)
                    // Check if all suggestions start with the same substring:
                    let commonPrefix = longestCommonPrefix(autocompleteSuggestions)
                    for i in 0..<autocompleteSuggestions.count {
                        var shortenedSugg = autocompleteSuggestions[i]
                        shortenedSugg.removeFirst(commonPrefix.count)
                        autocompleteSuggestions[i] = shortenedSugg
                    }
                    NSLog("suggestions: \(autocompleteSuggestions)")
                    commandBeforeCursor += commonPrefix
                    terminalView?.feed(text: commonPrefix)
                    if (autocompleteSuggestions.count > 1) {
                        terminalView?.saveCursorPosition()
                        printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                        terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                        terminalView?.restoreCursorPosition()
                        autocompleteRunning = true
                    } else if (commonPrefix.hasSuffix("/")) {
                        // Single suggestion, is a directory: fill again but don't force acceptance.
                        fillAutocompleteSuggestions(command: commandBeforeCursor)
                        if (autocompleteSuggestions.count > 0) {
                            terminalView?.saveCursorPosition()
                            printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                            terminalView?.restoreCursorPosition()
                            autocompleteRunning = true
                        } else {
                            autocompleteRunning = false
                        }
                    }
                }
            case escape + "OA": // up arrow (application mode)
                fallthrough
            case escape + "[A": // up arrow
                if (autocompleteRunning) {
                    autocompletePosition -= 1
                    if (autocompletePosition < 0) {
                        autocompletePosition = autocompleteSuggestions.count - 1
                    }
                    terminalView?.saveCursorPosition()
                    printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                    terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                    terminalView?.restoreCursorPosition()
                } else {
                    if (currentCommand == "") {
                        NSLog("Up arrow, position= \(historyPosition) count= \(history.count)")
                        if (historyPosition > 0) {
                            historyPosition -= 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView?.feed(text: history[historyPosition])
                            commandBeforeCursor = history[historyPosition]
                            commandAfterCursor = ""
                        }
                    } else {
                        NSLog("Up arrow, position= \(commandHistoryPosition) count= \(commandHistory.count)")
                        if (commandHistoryPosition > 0) {
                            commandHistoryPosition -= 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView!.setPromptEnd() // Required? Why?
                            terminalView?.feed(text: commandHistory[commandHistoryPosition])
                            commandBeforeCursor = commandHistory[commandHistoryPosition]
                            commandAfterCursor = ""
                        }
                    }
                }
            case escape + "OB": // down arrow (application mode)
                fallthrough
            case escape + "[B": // down arrow
                if (autocompleteRunning) {
                    autocompletePosition += 1
                    if (autocompletePosition > autocompleteSuggestions.count - 1) {
                        autocompletePosition = 0
                    }
                    terminalView?.saveCursorPosition()
                    printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                    terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                    terminalView?.restoreCursorPosition()
                } else {
                    if (currentCommand == "") {
                        NSLog("Down arrow, position= \(historyPosition) count= \(history.count)")
                        if (historyPosition < history.count - 1) {
                            historyPosition += 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            if (historyPosition < history.count) {
                                terminalView?.feed(text: history[historyPosition])
                                commandBeforeCursor = history[historyPosition]
                                commandAfterCursor = ""
                            }
                        } else {
                            historyPosition = history.count
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView?.getTerminal().updateFullScreen()
                            terminalView?.updateDisplay()
                            commandBeforeCursor = ""
                            commandAfterCursor = ""
                        }
                    } else {
                        NSLog("Down arrow, position= \(commandHistoryPosition) count= \(commandHistory.count)")
                        if (commandHistoryPosition < commandHistory.count - 1) {
                            commandHistoryPosition += 1
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            if (commandHistoryPosition < commandHistory.count) {
                                NSLog("sending \(commandHistory[commandHistoryPosition])")
                                terminalView?.feed(text: commandHistory[commandHistoryPosition])
                                commandBeforeCursor = commandHistory[commandHistoryPosition]
                                commandAfterCursor = ""
                            }
                        } else {
                            commandHistoryPosition = commandHistory.count
                            terminalView?.moveToBeginningOfLine()
                            terminalView?.clearToEndOfLine()
                            terminalView?.getTerminal().updateFullScreen()
                            terminalView?.updateDisplay()
                            commandBeforeCursor = ""
                            commandAfterCursor = ""
                        }
                    }
                }
            case escape + "OD": // left arrow (application mode)
                fallthrough
            case escape + "[D": // left arrow
                if autocompleteRunning {
                    stopAutocomplete()
                } else {
                    if (commandBeforeCursor.count > 0) {
                        if let lastChar = commandBeforeCursor.last {
                            commandBeforeCursor.removeLast()
                            commandAfterCursor = String(lastChar) + commandAfterCursor
                            terminalView?.moveUpIfNeeded()
                            let characterWidth = NSAttributedString(string: String(lastChar), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                terminalView?.feed(text: escape + "[D")
                            }
                            terminalView?.feed(text: escape + "[D")
                        }
                    }
                }
            case escape + "OC": // right arrow (application mode)
                fallthrough
            case escape + "[C": // right arrow
                if (autocompleteRunning) {
                    // autocomplete up to the next word boundary
                    let string = findNextWord(string: autocompleteSuggestions[autocompletePosition])
                    commandBeforeCursor += string
                    terminalView?.feed(text: string) // prints the string
                    updateAutocomplete(text: string)
                    if (commandBeforeCursor.hasSuffix("/") && (!autocompleteRunning || (autocompleteSuggestions[autocompletePosition].count == 0))) {
                        // We completed a directory. Let's list the content:
                        fillAutocompleteSuggestions(command: commandBeforeCursor)
                        if (autocompleteSuggestions.count > 0) {
                            terminalView?.saveCursorPosition()
                            printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                            terminalView?.restoreCursorPosition()
                            autocompleteRunning = true
                        } else {
                            autocompleteRunning = false
                        }
                    }
                } else {
                    if (commandAfterCursor.count > 0) {
                        if let firstChar = commandAfterCursor.first {
                            commandAfterCursor.removeFirst()
                            commandBeforeCursor = commandBeforeCursor + String(firstChar)
                            terminalView?.moveDownIfNeeded()
                            let characterWidth = NSAttributedString(string: String(firstChar), attributes: [.font: terminalView?.font]).size().width
                            if (characterWidth > 1.4 * basicCharWidth) {
                                terminalView?.feed(text: escape + "[C")
                            }
                            terminalView?.feed(text: escape + "[C")
                        }
                    } else {
                        NSLog("Cannot move right")
                    }
                }
            case "\u{0018}": // control X, stop autocomplete
                fallthrough
            case "\u{001A}": // control Z, stop autocomplete
                fallthrough
            case escape:    // escape, stop autocomplete
                if (autocompleteRunning) {
                    stopAutocomplete()
                }
            case carriageReturn:
                if (autocompleteRunning) {
                    // validate current suggestion
                    // overwrite suggestion in default color
                    terminalView?.feed(text: autocompleteSuggestions[autocompletePosition])
                    commandBeforeCursor += autocompleteSuggestions[autocompletePosition]
                    autocompleteSuggestions = []
                    autocompletePosition = 0
                    autocompleteRunning = false
                }
                if (currentCommand == "") {
                    let commandLine = (commandBeforeCursor + commandAfterCursor).trimmingCharacters(in: .whitespaces)
                    commandBeforeCursor = ""
                    commandAfterCursor = ""
                    executeCommand(command: commandLine)
                    terminalView?.feed(text: "\n\r")
                } else {
                    let commandLine = (commandBeforeCursor + commandAfterCursor).trimmingCharacters(in: .whitespaces)
                    commandBeforeCursor = ""
                    commandAfterCursor = ""
                    terminalView?.feed(text: "\n\r")
                    guard let data = (commandLine + "\n").data(using: .utf8) else { return }
                    guard stdin_file_input != nil else { return }
                    // store command in local command history, reset if it's different:
                    if (currentCommand != lastCommand) {
                        lastCommand = currentCommand
                        commandHistory = []
                        commandHistoryPosition = 0
                    }
                    if (commandHistory.last != commandLine) && (commandLine != "") {
                        commandHistory.append(commandLine)
                        while (commandHistory.count > 100) {
                            commandHistory.removeFirst()
                        }
                    }
                    commandHistoryPosition = commandHistory.count
                    // TODO: don't send data if pipe already closed (^D followed by another key)
                    // (store a variable that says the pipe has been closed)
                    stdin_file_input?.write(data)
                }
            default:
                // remove the Copy/Paste/etc menu if it is visible
                // Default, send to term
                commandBeforeCursor += string
                terminalView?.feed(text: string) // prints the string
                if autocompleteRunning {
                    updateAutocomplete(text: string)
                    if (commandBeforeCursor.hasSuffix("/") && (!autocompleteRunning || (autocompleteSuggestions[autocompletePosition].count == 0))) {
                        // We just completed a directory. Let's list the content:
                        fillAutocompleteSuggestions(command: commandBeforeCursor)
                        if (autocompleteSuggestions.count > 0) {
                            terminalView?.saveCursorPosition()
                            printAutocompleteString(suggestion: autocompleteSuggestions[autocompletePosition])
                            terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                            terminalView?.restoreCursorPosition()
                            autocompleteRunning = true
                        } else {
                            autocompleteRunning = false
                        }
                    }
                } else {
                    if (commandAfterCursor.count > 0) {
                        // redraw the end of the line
                        terminalView?.saveCursorPosition()
                        terminalView?.clearToEndOfLine()
                        terminalView?.feed(text: commandAfterCursor) // prints the rest of the line
                        terminalView?.restoreCursorPosition()
                    }
                }
            }
        } else {
            NSLog("Failure of conversion: \(data)")
        }
    }
    
    func scrolled(source: SwiftTerm.TerminalView, position: Double) {
        //
    }
    
    func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) {
        if let fixedup = link.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            if let url = NSURLComponents(string: fixedup) {
                if let nested = url.url {
                    UIApplication.shared.open (nested)
                }
            }
        }
    }
    
    func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
        if let str = String (bytes: content, encoding: .utf8) {
            UIPasteboard.general.string = str
        }
    }
    
    func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {
        //
    }
}
