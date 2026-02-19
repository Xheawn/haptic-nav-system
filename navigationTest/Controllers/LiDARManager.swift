//
//  LiDARManager.swift
//  navigationTest
//
//  8×8 grid depth analysis using ARKit smoothedSceneDepth.
//  Divides the 256×192 depth map into 64 cells (32×24 px each),
//  computes percentile-10 depth per cell, and publishes the grid
//  via a closure callback for UI display.
//

import Foundation
import ARKit

class LiDARManager: NSObject {

    static let shared = LiDARManager()

    // MARK: - Configurable parameters

    /// Distance (m) below which a cell is colored red (extreme danger)
    var dangerCloseDistance: Float = 0.5
    /// Distance (m) below which a cell is considered danger (orange)
    var dangerDistance: Float = 1.0
    /// Distance (m) below which a cell is considered caution zone
    var cautionDistance: Float = 2.0
    /// Horizontal gradient threshold (m) — obstacle edge detection
    var hGradientThreshold: Float = 1.0
    /// Vertical gradient threshold (m) — terrain discontinuity detection
    var vGradientThreshold: Float = 0.5
    /// Fraction of buffer x-axis to use (0.0–1.0). Lower = skip more near-ground data.
    /// 0.75 means use forward 75% of FOV, ignore bottom 25% (near feet).
    var forwardCropRatio: Float = 0.75
    /// How often to run analysis (seconds)
    var analysisInterval: TimeInterval = 0.2   // 5 Hz (balances responsiveness vs battery/heat)
    /// How often to print to console (seconds)
    var logInterval: TimeInterval = 0.5        // 2 Hz

    // MARK: - Grid constants

    static let gridRows = 16
    static let gridCols = 16
    // Portrait rotation: display row ↔ buffer x, display col ↔ buffer y
    // Buffer is 256(w) × 192(h)
    // cellPixelsX is computed dynamically based on forwardCropRatio
    static let cellPixelsY = 12   // 192 / 16 — maps to display cols (left→right)

    // MARK: - Public state

    /// Latest 8×8 depth grid (row-major). Each value = percentile-10 depth in meters.
    /// Access from main thread only.
    private(set) var depthGrid: [[Float]] = Array(
        repeating: Array(repeating: Float.greatestFiniteMagnitude, count: 16),
        count: 16
    )

    /// Callback invoked on main thread with the updated 8×8 grid.
    /// ViewController hooks into this to update the debug UI.
    var onGridUpdate: (([[Float]]) -> Void)?

    // MARK: - Private state

    private let session = ARSession()
    private var lastAnalysisTime: TimeInterval = 0
    private var lastLogTime: TimeInterval = 0

    // MARK: - Lifecycle

    /// Call once to start the ARSession with LiDAR depth.
    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("[LiDAR] This device does NOT support sceneDepth (needs LiDAR hardware)")
            return
        }

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = .sceneDepth
        session.delegate = self
        session.run(config)
        print("[LiDAR] ARSession started with smoothedSceneDepth (8×8 grid)")
    }

    func stop() {
        session.pause()
        print("[LiDAR] ARSession paused")
    }

    private override init() {
        super.init()
    }
}

// MARK: - ARSessionDelegate

extension LiDARManager: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = frame.timestamp

        // Throttle analysis
        guard now - lastAnalysisTime >= analysisInterval else { return }
        lastAnalysisTime = now

        // Prefer smoothedSceneDepth; fall back to sceneDepth
        guard let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }
        let depthMap = depthData.depthMap  // CVPixelBuffer, Float32, 256×192

        let grid = buildGrid(from: depthMap)
        self.depthGrid = grid

        // Notify UI on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onGridUpdate?(grid)
        }

        // Console log (throttled separately)
        if now - lastLogTime >= logInterval {
            lastLogTime = now
            printGrid(grid)
        }
    }
}

// MARK: - Grid computation

extension LiDARManager {

    /// Build a 16×16 grid from the depth map. Each cell = percentile-10 depth.
    /// Portrait rotation: display row ↔ buffer x-axis, display col ↔ buffer y-axis.
    private func buildGrid(from depthMap: CVPixelBuffer) -> [[Float]] {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let bufW = CVPixelBufferGetWidth(depthMap)    // 256
        let bufH = CVPixelBufferGetHeight(depthMap)    // 192
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return depthGrid
        }

        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatsPerRow = bytesPerRow / MemoryLayout<Float32>.size

        let rows = LiDARManager.gridRows   // 16
        let cols = LiDARManager.gridCols   // 16
        // Forward crop: only use the forward portion of buffer x range
        let usableX = Int(Float(bufW) * forwardCropRatio)  // e.g. 256*0.75 = 192
        let pxPerRow = max(1, usableX / rows)  // e.g. 192/16 = 12
        let pxPerCol = LiDARManager.cellPixelsY  // 12 px along buffer y → display col

        var grid = Array(repeating: Array(repeating: Float.greatestFiniteMagnitude, count: cols), count: rows)

        for row in 0..<rows {
            for col in 0..<cols {
                // Map: display row → buffer x, display col → buffer y (mirrored L↔R)
                let bxStart = row * pxPerRow
                let byStart = (cols - 1 - col) * pxPerCol  // mirror columns

                var cellDepths: [Float] = []
                cellDepths.reserveCapacity(pxPerRow * pxPerCol)

                for bx in bxStart..<min(bxStart + pxPerRow, bufW) {
                    for by in byStart..<min(byStart + pxPerCol, bufH) {
                        let d = floatBuffer[by * floatsPerRow + bx]
                        if d > 0 && !d.isNaN && !d.isInfinite {
                            cellDepths.append(d)
                        }
                    }
                }

                if cellDepths.isEmpty {
                    grid[row][col] = Float.greatestFiniteMagnitude
                } else {
                    // O(n) approximate percentile-10 using partitioning
                    grid[row][col] = Self.percentile10(&cellDepths)
                }
            }
        }

        return grid
    }

    /// O(n) approximate percentile-10 using partial selection.
    /// Much faster than full sort for 192-element arrays.
    private static func percentile10(_ arr: inout [Float]) -> Float {
        let k = max(0, Int(Float(arr.count) * 0.1))
        let target = min(k, arr.count - 1)
        // Use partial sort: only need the k-th smallest element
        // For small arrays (≤192), an insertion-based select is efficient
        if arr.count <= 1 { return arr[0] }
        // nth_element via introselect approximation: just partition once
        return kthSmallest(&arr, 0, arr.count - 1, target)
    }

    /// Quickselect to find k-th smallest element in O(n) average.
    private static func kthSmallest(_ arr: inout [Float], _ lo: Int, _ hi: Int, _ k: Int) -> Float {
        if lo == hi { return arr[lo] }

        // Median-of-three pivot
        let mid = lo + (hi - lo) / 2
        if arr[mid] < arr[lo] { arr.swapAt(lo, mid) }
        if arr[hi] < arr[lo] { arr.swapAt(lo, hi) }
        if arr[mid] < arr[hi] { arr.swapAt(mid, hi) }
        let pivot = arr[hi]

        var i = lo
        for j in lo..<hi {
            if arr[j] <= pivot {
                arr.swapAt(i, j)
                i += 1
            }
        }
        arr.swapAt(i, hi)

        if k == i {
            return arr[i]
        } else if k < i {
            return kthSmallest(&arr, lo, i - 1, k)
        } else {
            return kthSmallest(&arr, i + 1, hi, k)
        }
    }

    /// Print the 16×16 grid to console in a compact format.
    private func printGrid(_ grid: [[Float]]) {
        var output = "[LiDAR] 16×16 Depth Grid (p10, meters):\n"
        for row in 0..<grid.count {
            let cells = grid[row].map { val -> String in
                if val > 99 { return " -- " }
                return String(format: "%4.1f", val)
            }
            output += "  [\(cells.joined(separator: "|"))]\n"
        }
        print(output)
    }
}
