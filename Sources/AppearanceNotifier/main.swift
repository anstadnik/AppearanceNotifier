import AppKit
import Foundation
import ShellOut

private let kAppleInterfaceThemeChangedNotification = "AppleInterfaceThemeChangedNotification"

enum Theme {
    case light
    case dark
}

class ThemeChangeObserver {
    func observe() {
        print("Observing")

        DistributedNotificationCenter.default.addObserver(
            forName: Notification.Name(kAppleInterfaceThemeChangedNotification),
            object: nil,
            queue: nil,
            using: interfaceModeChanged(notification:)
        )
    }

    func interfaceModeChanged(notification _: Notification) {
        let themeRaw = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light"

        let theme = notificationToTheme(themeRaw: themeRaw)!

        notify(theme: theme)

        respond(theme: theme)
    }
}

func notificationToTheme(themeRaw: String) -> Theme? {
    return {
        switch themeRaw {
        case "Light":
            return Theme.light
        case "Dark":
            return Theme.dark
        default:
            return nil
        }
    }()
}

func notify(theme: Theme) {
    print("\(Date()) Theme changed: \(theme)")
}

func respond(theme: Theme) {
    do {
        // Neovim ---------------------------------------------------------------
        let output = try shellOut(to: "nvr", arguments: ["--serverlist"])
        let servers = output.split(whereSeparator: \.isNewline)

        if servers.isEmpty {
            print("\(Date()) neovim: no servers")
        } else {
            servers.forEach { server in
                let server = String(server)

                print("\(Date()) neovim server (\(String(server))): sending command")

                let arguments = buildNvimBackgroundArguments(server: server, theme: theme)

                DispatchQueue.global().async {
                    do {
                        try shellOut(to: "nvr", arguments: arguments)
                    } catch {
                        print("\(Date()) neovim server \(String(server)): command failed")
                    }
                }
            }
        }

        DispatchQueue.global().async {
            print("\(Date()) neovim: updating config")

            let arguments = [
                "-E",
                "-i",
                // Don't create a backfup file
                "''",
                "\"s/vim.opt.background = \\\"[a-z]*\\\"/vim.opt.background = \\\"\(themeToStringTheme(theme: theme))\\\"/g\"",
                "~/.config/nvim/lua/plugins/color.lua"
            ]

            do {
                try shellOut(to: "sed", arguments: arguments)
            } catch {
                print("\(Date()) neovim: config update failed")
            }
        }

        // Kitty ----------------------------------------------------------------
        DispatchQueue.global().async {
            print("\(Date()) kitty: sending command")

            let arguments = buildKittyArguments(theme: theme)

            do {
                try shellOut(to: "kitty", arguments: arguments)
            } catch {
                print("\(Date()) kitty: command failed")
            }
        }

        // Tmux -----------------------------------------------------------------
        DispatchQueue.global().async {
            print("\(Date()) tmux: sending command")

            let arguments1 = ["set", "-g", "@catppuccin_flavour", themeToCatppuccinTheme(theme: theme)]
            let arguments2 = ["run-shell", "~/.tmux/plugins/tpm/tpm"]

            do {
                try shellOut(to: "tmux", arguments: arguments1)
                try shellOut(to: "tmux", arguments: arguments2)
            } catch {
                print("\(Date()) tmux: command failed")
            }
        }

        // Helix ----------------------------------------------------------------
        DispatchQueue.global().async {
            print("\(Date()) helix: updating config")

            let arguments = [
                "-E",
                "-i",
                // Don't create a backfup file
                "''",
                "s/catppuccin_[a-z]*/catppuccin_\(themeToCatppuccinTheme(theme: theme))/g",
                "~/.config/helix/config.toml",
            ]

            do {
                try shellOut(to: "sed", arguments: arguments)
            } catch {
                print("\(Date()) helix: config update failed")
            }
        }

        DispatchQueue.global().async {
            print("\(Date()) helix: reloading config")

            let arguments = ["-USR1", "hx"]

            do {
                try shellOut(to: "pkill", arguments: arguments)
            } catch {
                print("\(Date()) helix: config reload failed")
            }
        }

        DispatchQueue.global().async {
            // Emacs ----------------------------------------------------------------
            DispatchQueue.global().async {
                print("\(Date()) emacs: sending command")

                let arguments = buildEmacsArguments(theme: theme)

                do {
                    try shellOut(to: "emacsclient", arguments: arguments)
                } catch {
                    print("\(Date()) emacs: command failed: \(error)")
                }
            }
        }
    } catch {
        let error = error as! ShellOutError
        print(error.message) // Prints STDERR
        print(error.output) // Prints STDOUT
    }
}

func buildNvimBackgroundArguments(server: String, theme: Theme) -> [String] {
//    return ["--servername", server, "+'colorscheme catppuccin-\(themeToCatppuccinTheme(theme: theme))'"]
    return ["--servername", server, "+'set background=\(themeToStringTheme(theme: theme))'"]
}

func buildKittyArguments(theme: Theme) -> [String] {
    return [
        "+kitten",
        "themes",
        "--reload-in=all",
        "--config-file-name",
        "themes.conf",
        "Catppuccin-\(themeToCatppuccinTheme(theme: theme).capitalized)",
    ]
}

func buildEmacsArguments(theme: Theme) -> [String] {
    return [
        "--socket-name",
        "~/.config/emacs/server/server",
        "--eval",
        #""(my/catppuccin-set-and-reload '\#(themeToCatppuccinTheme(theme: theme)))""#,
        "--quiet",
        "-no-wait",
        "--suppress-output",
        "-a",
        "true",
    ]
}

func themeToCatppuccinTheme(theme: Theme) -> String {
    return {
        switch theme {
        case .light:
            return "latte"
        case .dark:
            return "mocha"
        }
    }()
}

func themeToStringTheme(theme: Theme) -> String {
    return {
        switch theme {
        case .light:
            return "light"
        case .dark:
            return "dark"
        }
    }()
}

func toSnakeCase(sentence: String) -> String {
    let lowercaseSentence = sentence.lowercased()

    return lowercaseSentence.replacingOccurrences(of: " ", with: "_")
}

func toKebabCase(sentence: String) -> String {
    let lowercaseSentence = sentence.lowercased()

    return lowercaseSentence.replacingOccurrences(of: " ", with: "-")
}

let app = NSApplication.shared

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        let observer = ThemeChangeObserver()
        observer.observe()
    }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
