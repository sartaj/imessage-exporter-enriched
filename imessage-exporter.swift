#!/usr/bin/env swift

import Foundation
import Contacts

// MARK: - Configuration
struct ExportConfig {
    let outputDirectory: String
    let format: String // "txt" or "html"
    let copyMethod: String // "disabled", "clone", "basic", "full"
    let databasePath: String?
    let attachmentPath: String?
    let startDate: String?
    let endDate: String?
    let verbose: Bool
    let dryRun: Bool
    let renameFiles: Bool
}

// MARK: - Utility Functions
func cleanPhoneNumber(_ phone: String) -> [String] {
    // Remove all non-digit characters except +
    let cleaned = phone.replacingOccurrences(of: "[^\\d+]", with: "", options: .regularExpression)
    
    var variations: [String] = []
    
    // Handle different formats and generate multiple variations
    if cleaned.hasPrefix("+1") && cleaned.count == 12 {
        // +1XXXXXXXXXX
        variations.append(cleaned)
        variations.append(String(cleaned.dropFirst(2))) // XXXXXXXXXX
        variations.append("1\(cleaned.dropFirst(2))") // 1XXXXXXXXXX
    } else if cleaned.hasPrefix("1") && cleaned.count == 11 {
        // 1XXXXXXXXXX
        variations.append("+\(cleaned)")
        variations.append(cleaned)
        variations.append(String(cleaned.dropFirst())) // XXXXXXXXXX
    } else if cleaned.count == 10 {
        // XXXXXXXXXX
        variations.append("+1\(cleaned)")
        variations.append("1\(cleaned)")
        variations.append(cleaned)
    } else if cleaned.hasPrefix("+") {
        // Keep international format as-is
        variations.append(cleaned)
    }
    
    // Also add the original if it's different
    if !variations.contains(phone) {
        variations.append(phone)
    }
    
    return variations.filter { !$0.isEmpty }
}

func sanitizeFilename(_ filename: String) -> String {
    let invalidChars = CharacterSet(charactersIn: "<>:\"/\\|?*")
    let sanitized = filename.components(separatedBy: invalidChars).joined(separator: "_")
    
    // Remove multiple consecutive underscores
    let regex = try! NSRegularExpression(pattern: "_{2,}", options: [])
    let result = regex.stringByReplacingMatches(in: sanitized, options: [], range: NSRange(location: 0, length: sanitized.count), withTemplate: "_")
    
    // Remove leading/trailing underscores
    return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
}

func extractIdentifiersFromFilename(_ filename: String) -> [String] {
    var identifiers: [String] = []
    
    // Remove file extension
    let nameWithoutExt = (filename as NSString).deletingPathExtension
    
    // Split by comma and clean each part
    let parts = nameWithoutExt.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    
    for part in parts {
        // Check if it's a phone number (contains digits)
        if part.range(of: "\\d", options: .regularExpression) != nil {
            let cleanedPhones = cleanPhoneNumber(part)
            for cleanedPhone in cleanedPhones {
                identifiers.append(cleanedPhone)
            }
        }
        // Check if it's an email address
        else if part.contains("@") {
            identifiers.append(part.lowercased().trimmingCharacters(in: .whitespaces))
        }
    }
    
    return identifiers
}

// MARK: - iMessage Export
func runImessageExporter(config: ExportConfig) -> Bool {
    print("Running iMessage export...")
    
    var arguments = ["imessage-exporter"]
    
    // Add format
    arguments.append("-f")
    arguments.append(config.format)
    
    // Add copy method
    arguments.append("-c")
    arguments.append(config.copyMethod)
    
    // Add output directory
    arguments.append("-o")
    arguments.append(config.outputDirectory)
    
    // Add optional parameters
    if let dbPath = config.databasePath {
        arguments.append("-p")
        arguments.append(dbPath)
    }
    
    if let attachmentPath = config.attachmentPath {
        arguments.append("-r")
        arguments.append(attachmentPath)
    }
    
    if let startDate = config.startDate {
        arguments.append("-s")
        arguments.append(startDate)
    }
    
    if let endDate = config.endDate {
        arguments.append("-e")
        arguments.append(endDate)
    }
    
    if config.verbose {
        print("Running command: \(arguments.joined(separator: " "))")
    }
    
    // Create and run the process
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    
    do {
        try process.run()
        process.waitUntilExit()
        
        // Capture output
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
            print("iMessage Exporter output:")
            print(output)
        }
        
        if process.terminationStatus == 0 {
            print("✓ iMessage export completed successfully")
            return true
        } else {
            print("✗ iMessage export failed with exit code: \(process.terminationStatus)")
            return false
        }
        
    } catch {
        print("Error running imessage-exporter: \(error)")
        print("Make sure imessage-exporter is installed and in your PATH")
        print("You can install it from: https://github.com/ReagentX/imessage-exporter")
        return false
    }
}

// MARK: - Contacts Access
func loadContacts(verbose: Bool) -> [String: String] {
    let store = CNContactStore()
    var contactMap: [String: String] = [:]
    
    // Request permission
    var authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    
    if authorizationStatus == .notDetermined {
        let semaphore = DispatchSemaphore(value: 0)
        store.requestAccess(for: .contacts) { granted, error in
            if let error = error {
                print("Error requesting contacts access: \(error)")
            }
            authorizationStatus = granted ? .authorized : .denied
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    guard authorizationStatus == .authorized else {
        print("Error: Contacts access not authorized. Please grant access in System Preferences → Security & Privacy → Privacy → Contacts")
        return [:]
    }
    
    // Keys to fetch
    let keysToFetch = [
        CNContactGivenNameKey,
        CNContactFamilyNameKey,
        CNContactOrganizationNameKey,
        CNContactPhoneNumbersKey,
        CNContactEmailAddressesKey
    ] as [CNKeyDescriptor]
    
    do {
        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contactCount = 0
        var phoneCount = 0
        var emailCount = 0
        
        try store.enumerateContacts(with: request) { contact, _ in
            contactCount += 1
            
            // Build contact name
            var nameParts: [String] = []
            if !contact.givenName.isEmpty {
                nameParts.append(contact.givenName)
            }
            if !contact.familyName.isEmpty {
                nameParts.append(contact.familyName)
            }
            
            let fullName: String
            if !nameParts.isEmpty {
                fullName = nameParts.joined(separator: " ")
            } else if !contact.organizationName.isEmpty {
                fullName = contact.organizationName
            } else {
                return // Skip contacts without names
            }
            
            // Add phone numbers
            for phoneNumber in contact.phoneNumbers {
                let phone = phoneNumber.value.stringValue
                let cleanedPhones = cleanPhoneNumber(phone)
                for cleanedPhone in cleanedPhones {
                    contactMap[cleanedPhone] = fullName
                    phoneCount += 1
                }
            }
            
            // Add email addresses
            for email in contact.emailAddresses {
                let emailAddress = String(email.value).lowercased()
                contactMap[emailAddress] = fullName
                emailCount += 1
            }
        }
        
        if verbose {
            print("Loaded \(contactCount) contacts")
            print("Mapped \(phoneCount) phone numbers")
            print("Mapped \(emailCount) email addresses")
            print("Total contact identifiers: \(contactMap.count)")
        }
        
    } catch {
        print("Error fetching contacts: \(error)")
    }
    
    return contactMap
}

// MARK: - Timestamp Management
func updateFileTimestamps(in exportDir: String, verbose: Bool) {
    print("📅 Updating file timestamps based on message dates...")
    
    let fileManager = FileManager.default
    let exportURL = URL(fileURLWithPath: NSString(string: exportDir).expandingTildeInPath)
    
    guard fileManager.fileExists(atPath: exportURL.path) else {
        print("Error: Export directory not found: \(exportDir)")
        return
    }
    
    do {
        let files = try fileManager.contentsOfDirectory(at: exportURL, includingPropertiesForKeys: nil)
        let exportFiles = files.filter { file in
            let pathExtension = file.pathExtension.lowercased()
            return pathExtension == "txt" || pathExtension == "html"
        }
        
        if verbose {
            print("Found \(exportFiles.count) export files to process")
        }
        
        var updatedCount = 0
        
        for fileURL in exportFiles {
            if verbose {
                print("Processing \(fileURL.lastPathComponent)...")
            }
            
            if let (firstMessageDate, lastMessageDate) = extractMessageDates(from: fileURL, verbose: verbose) {
                do {
                    // Set creation date to first message, modification date to last message
                    try fileManager.setAttributes([
                        .creationDate: firstMessageDate,
                        .modificationDate: lastMessageDate
                    ], ofItemAtPath: fileURL.path)
                    
                    updatedCount += 1
                    
                    if verbose {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .medium
                        formatter.timeStyle = .short
                        
                        print("  ✅ Updated \(fileURL.lastPathComponent):")
                        print("    Created: \(formatter.string(from: firstMessageDate))")
                        print("    Modified: \(formatter.string(from: lastMessageDate))")
                    }
                } catch {
                    print("  ❌ Error updating timestamps for \(fileURL.lastPathComponent): \(error)")
                }
            } else {
                if verbose {
                    print("  ⚠️  Could not extract dates from \(fileURL.lastPathComponent)")
                }
            }
        }
        
        print("✅ Updated timestamps for \(updatedCount) files")
        
    } catch {
        print("Error reading export directory: \(error)")
    }
}

func extractMessageDates(from fileURL: URL, verbose: Bool) -> (Date, Date)? {
    do {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let pathExtension = fileURL.pathExtension.lowercased()
        
        if verbose {
            print("    File extension: \(pathExtension)")
            print("    Content preview (first 500 chars):")
            print("    \(String(content.prefix(500)))")
        }
        
        var dates: [Date] = []
        
        if pathExtension == "txt" {
            dates = extractDatesFromTxt(content: content)
        } else if pathExtension == "html" {
            dates = extractDatesFromHtml(content: content)
        }
        
        if verbose {
            print("    Found \(dates.count) timestamps")
            if !dates.isEmpty {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .short
                let sortedDates = dates.sorted()
                print("    First: \(formatter.string(from: sortedDates.first!))")
                print("    Last: \(formatter.string(from: sortedDates.last!))")
            }
        }
        
        guard !dates.isEmpty else {
            if verbose {
                print("    ❌ No dates found in file")
            }
            return nil
        }
        
        let sortedDates = dates.sorted()
        let firstDate = sortedDates.first!
        let lastDate = sortedDates.last!
        
        return (firstDate, lastDate)
        
    } catch {
        if verbose {
            print("    ❌ Error reading file: \(error)")
        }
        return nil
    }
}

func extractDatesFromTxt(content: String) -> [Date] {
    var dates: [Date] = []
    
    // TXT format from imessage-exporter has timestamps on their own lines like:
    // Nov 28, 2024 11:46:34 AM
    // Nov 29, 2024  2:19:59 PM (note: sometimes extra spaces before time)
    
    let patterns = [
        // Primary format: "Nov 28, 2024 11:46:34 AM" or "Nov 29, 2024  2:19:59 PM"
        // This matches timestamps at the start of a line, with possible extra spaces
        "^(\\w{3} \\d{1,2}, \\d{4})\\s+(\\d{1,2}:\\d{2}:\\d{2} [AP]M)",
        // Alternative: timestamps anywhere in line (fallback)
        "(\\w{3} \\d{1,2}, \\d{4})\\s+(\\d{1,2}:\\d{2}:\\d{2} [AP]M)",
        // ISO-like format with brackets (legacy): [2023-12-25, 14:30:45]
        "\\[(\\d{4}-\\d{2}-\\d{2})[, ]+(\\d{2}:\\d{2}:\\d{2})\\]",
        // ISO format without brackets: 2023-12-25 14:30:45
        "(\\d{4}-\\d{2}-\\d{2}) (\\d{2}:\\d{2}:\\d{2})"
    ]
    
    let formatters = [
        createFormatter(format: "MMM d, yyyy h:mm:ss a"),  // Nov 28, 2024 11:46:34 AM
        createFormatter(format: "MMM d, yyyy h:mm:ss a"),  // Same as above
        createFormatter(format: "yyyy-MM-dd HH:mm:ss"),    // 2023-12-25 14:30:45
        createFormatter(format: "yyyy-MM-dd HH:mm:ss")     // 2023-12-25 14:30:45
    ]
    
    for (index, pattern) in patterns.enumerated() {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        for match in matches {
            if match.numberOfRanges >= 3 {
                let dateRange = Range(match.range(at: 1), in: content)!
                let timeRange = Range(match.range(at: 2), in: content)!
                
                let dateStr = String(content[dateRange])
                let timeStr = String(content[timeRange])
                let fullDateStr = "\(dateStr) \(timeStr)"
                
                if let date = formatters[index].date(from: fullDateStr) {
                    dates.append(date)
                }
            }
        }
        
        // If we found dates with this pattern, no need to try others
        if !dates.isEmpty {
            break
        }
    }
    
    return dates
}

func extractDatesFromHtml(content: String) -> [Date] {
    var dates: [Date] = []
    
    // HTML format typically has timestamps in various formats
    let patterns = [
        // Look for datetime attributes: datetime="2023-12-25T14:30:45"
        "datetime=\"([^\"]+)\"",
        // Look for timestamp spans or divs
        "class=\"timestamp\"[^>]*>([^<]+)<",
        // ISO format in text: 2023-12-25 14:30:45
        "(\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}:\\d{2})",
        // Date with "at" format in HTML
        "(\\w{3} \\d{1,2}, \\d{4}) at (\\d{1,2}:\\d{2}:\\d{2} [AP]M)"
    ]
    
    let formatters = [
        createFormatter(format: "yyyy-MM-dd'T'HH:mm:ss"),
        createFormatter(format: "MMM d, yyyy 'at' h:mm:ss a"),
        createFormatter(format: "yyyy-MM-dd HH:mm:ss"),
        createFormatter(format: "MMM d, yyyy h:mm:ss a")
    ]
    
    // Try ISO 8601 formatter first for datetime attributes
    let iso8601Formatter = ISO8601DateFormatter()
    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    
    for (index, pattern) in patterns.enumerated() {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let matches = regex.matches(in: content, options: [], range: NSRange(content.startIndex..., in: content))
        
        for match in matches {
            if index == 0 { // datetime attribute
                let range = Range(match.range(at: 1), in: content)!
                let dateStr = String(content[range])
                
                // Try ISO8601 first, then fall back to custom formatter
                if let date = iso8601Formatter.date(from: dateStr) {
                    dates.append(date)
                } else if let date = formatters[0].date(from: dateStr) {
                    dates.append(date)
                }
            } else if index == 3 { // Date with "at" format
                if match.numberOfRanges >= 3 {
                    let dateRange = Range(match.range(at: 1), in: content)!
                    let timeRange = Range(match.range(at: 2), in: content)!
                    
                    let dateStr = String(content[dateRange])
                    let timeStr = String(content[timeRange])
                    let fullDateStr = "\(dateStr) \(timeStr)"
                    
                    if let date = formatters[3].date(from: fullDateStr) {
                        dates.append(date)
                    }
                }
            } else {
                let range = Range(match.range(at: 1), in: content)!
                let dateStr = String(content[range]).trimmingCharacters(in: .whitespaces)
                
                if let date = formatters[index].date(from: dateStr) {
                    dates.append(date)
                }
            }
        }
    }
    
    return dates
}

func createFormatter(format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter
}
func renameFiles(in exportDir: String, contacts: [String: String], dryRun: Bool, verbose: Bool) {
    let fileManager = FileManager.default
    let exportURL = URL(fileURLWithPath: NSString(string: exportDir).expandingTildeInPath)
    
    guard fileManager.fileExists(atPath: exportURL.path) else {
        print("Error: Export directory not found: \(exportDir)")
        return
    }
    
    do {
        let files = try fileManager.contentsOfDirectory(at: exportURL, includingPropertiesForKeys: nil)
        let exportFiles = files.filter { file in
            let pathExtension = file.pathExtension.lowercased()
            return (pathExtension == "txt" || pathExtension == "html") && 
                   (file.lastPathComponent.range(of: "[\\d@]", options: .regularExpression) != nil)
        }
        
        if verbose {
            print("Found \(exportFiles.count) files to potentially rename")
        }
        
        var renamedCount = 0
        var unmatchedCount = 0
        
        for fileURL in exportFiles {
            let filename = fileURL.lastPathComponent
            let identifiers = extractIdentifiersFromFilename(filename)
            
            if verbose {
                print("Processing file: \(filename)")
                print("  Extracted identifiers: \(identifiers)")
            }
            
            var matchedNames: [String] = []
            for identifier in identifiers {
                if let contactName = contacts[identifier] {
                    if !matchedNames.contains(contactName) {
                        matchedNames.append(contactName)
                    }
                    if verbose {
                        print("  ✓ Matched: \(identifier) -> \(contactName)")
                    }
                } else if verbose {
                    print("  ✗ No match for: \(identifier)")
                }
            }
            
            if verbose {
                print("  Final matched names: \(matchedNames)")
                print()
            }
            
            if !matchedNames.isEmpty {
                // Create new filename with contact names
                let newName = matchedNames.joined(separator: ", ")
                let sanitizedName = sanitizeFilename(newName)
                let newFilename = "\(sanitizedName).\(fileURL.pathExtension)"
                var newFileURL = exportURL.appendingPathComponent(newFilename)
                
                // Handle filename conflicts
                var counter = 1
                while fileManager.fileExists(atPath: newFileURL.path) && newFileURL != fileURL {
                    let baseName = "\(sanitizedName) (\(counter))"
                    let conflictFilename = "\(baseName).\(fileURL.pathExtension)"
                    newFileURL = exportURL.appendingPathComponent(conflictFilename)
                    counter += 1
                }
                
                if newFileURL != fileURL {
                    if verbose || dryRun {
                        print("\(dryRun ? "[DRY RUN] " : "")Renaming:")
                        print("  From: \(filename)")
                        print("  To:   \(newFileURL.lastPathComponent)")
                    }
                    
                    if !dryRun {
                        do {
                            try fileManager.moveItem(at: fileURL, to: newFileURL)
                            renamedCount += 1
                            
                            if verbose {
                                print("  ✓ Successfully renamed")
                            }
                        } catch {
                            print("Error renaming \(filename): \(error)")
                        }
                    } else {
                        renamedCount += 1
                    }
                    
                    if verbose || dryRun {
                        print()
                    }
                }
            } else {
                unmatchedCount += 1
                if verbose {
                    print("No matching contacts found for: \(filename)")
                }
            }
        }
        
        // Summary
        if dryRun {
            print("Would rename \(renamedCount) files")
            if unmatchedCount > 0 {
                print("\(unmatchedCount) files had no matching contacts")
            }
        } else {
            print("Renamed \(renamedCount) files")
            if unmatchedCount > 0 && verbose {
                print("\(unmatchedCount) files had no matching contacts")
            }
        }
        
    } catch {
        print("Error reading export directory: \(error)")
    }
}

// MARK: - Main Function
func printUsage() {
    print("Usage: swift imessage_complete.swift [options]")
    print("")
    print("Options:")
    print("  -o, --output DIR          Output directory (default: ./imessage_export)")
    print("  -f, --format FORMAT       Export format: txt or html (default: txt)")
    print("  -c, --copy-method METHOD  Attachment copy method: disabled, clone, basic, full (default: disabled)")
    print("  -p, --db-path PATH        Custom iMessage database path")
    print("  -r, --attachment-root PATH Custom attachment root path")
    print("  -s, --start-date DATE     Start date (YYYY-MM-DD)")
    print("  -e, --end-date DATE       End date (YYYY-MM-DD)")
    print("  --no-rename               Skip contact name renaming")
    print("  --dry-run                 Show what would be done without making changes")
    print("  --verbose                 Show detailed output")
    print("  -h, --help                Show this help message")
    print("")
    print("Examples:")
    print("  swift imessage_complete.swift")
    print("  swift imessage_complete.swift -f html -c basic -o ~/Documents/messages")
    print("  swift imessage_complete.swift --dry-run --verbose")
    print("  swift imessage_complete.swift -s 2023-01-01 -e 2023-12-31")
}

func parseArguments() -> ExportConfig? {
    let arguments = Array(CommandLine.arguments.dropFirst())
    
    var outputDirectory = "./imessage_export"  // Default to current directory
    var format = "txt"
    var copyMethod = "disabled"
    var databasePath: String? = nil
    var attachmentPath: String? = nil
    var startDate: String? = nil
    var endDate: String? = nil
    var verbose = false
    var dryRun = false
    var renameFiles = true
    
    var i = 0
    while i < arguments.count {
        let arg = arguments[i]
        
        switch arg {
        case "-h", "--help":
            printUsage()
            return nil
        case "-o", "--output":
            guard i + 1 < arguments.count else {
                print("Error: --output requires a directory argument")
                return nil
            }
            outputDirectory = arguments[i + 1]
            i += 1
        case "-f", "--format":
            guard i + 1 < arguments.count else {
                print("Error: --format requires an argument (txt or html)")
                return nil
            }
            format = arguments[i + 1]
            guard ["txt", "html"].contains(format) else {
                print("Error: format must be 'txt' or 'html'")
                return nil
            }
            i += 1
        case "-c", "--copy-method":
            guard i + 1 < arguments.count else {
                print("Error: --copy-method requires an argument")
                return nil
            }
            copyMethod = arguments[i + 1]
            guard ["disabled", "clone", "basic", "full"].contains(copyMethod) else {
                print("Error: copy-method must be one of: disabled, clone, basic, full")
                return nil
            }
            i += 1
        case "-p", "--db-path":
            guard i + 1 < arguments.count else {
                print("Error: --db-path requires a path argument")
                return nil
            }
            databasePath = arguments[i + 1]
            i += 1
        case "-r", "--attachment-root":
            guard i + 1 < arguments.count else {
                print("Error: --attachment-root requires a path argument")
                return nil
            }
            attachmentPath = arguments[i + 1]
            i += 1
        case "-s", "--start-date":
            guard i + 1 < arguments.count else {
                print("Error: --start-date requires a date argument (YYYY-MM-DD)")
                return nil
            }
            startDate = arguments[i + 1]
            i += 1
        case "-e", "--end-date":
            guard i + 1 < arguments.count else {
                print("Error: --end-date requires a date argument (YYYY-MM-DD)")
                return nil
            }
            endDate = arguments[i + 1]
            i += 1
        case "--no-rename":
            renameFiles = false
        case "--dry-run":
            dryRun = true
        case "--verbose":
            verbose = true
        default:
            print("Error: Unknown argument '\(arg)'")
            print("Use --help for usage information")
            return nil
        }
        
        i += 1
    }
    
    return ExportConfig(
        outputDirectory: outputDirectory,
        format: format,
        copyMethod: copyMethod,
        databasePath: databasePath,
        attachmentPath: attachmentPath,
        startDate: startDate,
        endDate: endDate,
        verbose: verbose,
        dryRun: dryRun,
        renameFiles: renameFiles
    )
}

func main() {
    guard let config = parseArguments() else {
        exit(1)
    }
    
    print("🚀 iMessage Complete Export & Rename Tool")
    print("=" * 50)
    
    if config.dryRun {
        print("⚠️  DRY RUN MODE - No files will be created or modified")
        print()
    }
    
    if config.verbose {
        print("Configuration:")
        print("  Output directory: \(config.outputDirectory)")
        print("  Format: \(config.format)")
        print("  Copy method: \(config.copyMethod)")
        print("  Database path: \(config.databasePath ?? "default")")
        print("  Attachment path: \(config.attachmentPath ?? "default")")
        print("  Start date: \(config.startDate ?? "none")")
        print("  End date: \(config.endDate ?? "none")")
        print("  Rename files: \(config.renameFiles)")
        print()
    }
    
    // Step 1: Run iMessage export
    if !config.dryRun {
        let exportSuccess = runImessageExporter(config: config)
        if !exportSuccess {
            print("❌ Export failed. Exiting.")
            exit(1)
        }
    } else {
        print("🔍 DRY RUN: Would run iMessage export with current settings")
    }
    
    // Step 2: Rename files with contact names (if enabled)
    if config.renameFiles {
        print("\n" + "=" * 50)
        print("📇 Loading contacts and renaming files...")
        
        let contacts = loadContacts(verbose: config.verbose)
        
        if contacts.isEmpty {
            print("⚠️  No contacts found or contacts access denied. Files will keep original names.")
        } else {
            if config.verbose {
                print("\nSample contacts loaded:")
                let sampleContacts = Array(contacts.prefix(5))
                for (identifier, name) in sampleContacts {
                    print("  \(identifier) -> \(name)")
                }
                if contacts.count > 5 {
                    print("  ... and \(contacts.count - 5) more")
                }
                print()
            }
            
            renameFiles(in: config.outputDirectory, contacts: contacts, dryRun: config.dryRun, verbose: config.verbose)
        }
    } else {
        print("📝 Skipping file renaming (--no-rename specified)")
    }
    
    // Step 3: Update file timestamps based on message dates
    if !config.dryRun {
        print("\n" + "=" * 50)
        updateFileTimestamps(in: config.outputDirectory, verbose: config.verbose)
    } else {
        print("\n" + "=" * 50)
        print("🔍 DRY RUN: Would update file timestamps based on message dates")
    }
    
    print("\n" + "=" * 50)
    if config.dryRun {
        print("✅ Dry run completed. Use without --dry-run to actually export and rename files.")
    } else {
        print("✅ Export and rename completed!")
        print("📁 Files available at: \(config.outputDirectory)")
    }
}

// String repeat extension
extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}

// Run the main function
main()
