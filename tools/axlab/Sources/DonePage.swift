import Foundation


/// Opens a page in the browser when a run ends (or stops), so whoever stepped away from the
/// keyboard knows they can use the Mac again, and sees the results right there.
func openDonePage(_ reports: [TargetReport], stopped: Abort?, total: Int, in directory: URL) throws {
  let ran = reports.compactMap { report -> [CaseResult]? in
    if case .ran(let results) = report.outcome { results } else { nil }
  }
  let passedTargets = ran.filter { $0.allSatisfy(\.passed) }.count
  let failedTargets = reports.filter { if case .failed = $0.outcome { true } else { false } }.count
  let title = stopped == nil ? "All done" : "Stopped"
  let lead = stopped.map { "The run stopped: \(escape($0.description))." }
    ?? "\(passedTargets) of \(ran.count) targets passed every case"
      + (failedTargets > 0 ? ", \(failedTargets) couldn't be tested" : "") + "."

  var rows = ""
  for report in reports {
    let id = escape(report.target.id)
    var details: [String] = report.notes.map(escape)
    let status: String
    switch report.outcome {
    case .skipped(let reason):
      status = "<span class=muted>skipped</span>"
      details.append(escape(reason))
    case .failed(let reason):
      status = "<span class=bad>not tested</span>"
      details.append(escape(reason))
    case .ran(let results):
      let passed = results.filter(\.passed).count
      status = "<span class=\(passed == results.count ? "good" : "bad")>\(passed)/\(results.count)</span>"
      for result in results where !result.passed {
        details.append("case \(result.number): got \(escape(show(result.result))), expected \(escape(show(result.expected)))")
      }
    }
    let time = String(format: "%.1fs", report.duration)
    rows += "<tr><td>\(id)</td><td>\(status)</td><td class=muted>\(time)</td><td>\(details.joined(separator: "<br>"))</td></tr>\n"
  }
  if reports.count < total {
    rows += "<tr><td colspan=4 class=muted>\(total - reports.count) targets not reached</td></tr>\n"
  }

  let html = """
    <!doctype html>
    <html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>axlab: \(title)</title>
    <style>
      :root { color-scheme: light dark; --bg: #fafaf9; --fg: #1c1917; --muted: #78716c;
              --line: #e7e5e4; --good: #15803d; --bad: #b91c1c; }
      @media (prefers-color-scheme: dark) {
        :root { --bg: #1c1917; --fg: #f5f5f4; --muted: #a8a29e; --line: #44403c;
                --good: #4ade80; --bad: #f87171; }
      }
      body { background: var(--bg); color: var(--fg); margin: 0;
             font: 15px/1.5 -apple-system, BlinkMacSystemFont, sans-serif; }
      main { max-width: 960px; margin: 0 auto; padding: 48px 16px; }
      h1 { font-size: 44px; margin: 0 0 4px; }
      .lead { font-size: 18px; margin: 0 0 32px; }
      table { width: 100%; border-collapse: collapse; }
      td { padding: 8px 12px 8px 0; border-top: 1px solid var(--line); vertical-align: top; }
      td:first-child { font-family: ui-monospace, monospace; white-space: nowrap; }
      .good { color: var(--good); font-weight: 600; } .bad { color: var(--bad); font-weight: 600; }
      .muted { color: var(--muted); }
      code { font-family: ui-monospace, monospace; }
    </style></head>
    <body><main>
      <h1>\(title)</h1>
      <p class="lead">You can use your Mac again. \(lead)</p>
      <table>\(rows)</table>
      <p class="muted">Captures and summary: <code>\(escape(directory.path))</code></p>
    </main></body></html>
    """
  let page = directory.appending(path: "done.html")
  try html.write(to: page, atomically: true, encoding: .utf8)
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
  process.arguments = [page.path]
  try process.run()
  process.waitUntilExit()
}

private func escape(_ text: String) -> String {
  text.replacingOccurrences(of: "&", with: "&amp;")
    .replacingOccurrences(of: "<", with: "&lt;")
    .replacingOccurrences(of: ">", with: "&gt;")
}
