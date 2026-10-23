import SwiftUI
import AVKit

struct PlaybackSurface: View {
    let player: AVPlayer
    let title: String
    var expanded = false
    var close: (() -> Void)? = nil
    @State private var fullscreen = false
    @State private var locked = false
    @State private var controls = true
    @State private var fill = false
    @State private var speed: Float = 1
    @State private var scrub: Double?
    @State private var muted = false
    @State private var dragStart: Double?
    @State private var dragTarget: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if !fullscreen {
                    PlayerLayerView(player: player, fill: fill)
                }
                Color.clear.contentShape(Rectangle()).onTapGesture { controls.toggle() }
                    .gesture(DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            guard !locked, abs(value.translation.width) > abs(value.translation.height),
                                  let target = PlaybackSeeking.target(
                                    start: dragStart ?? player.currentTime().seconds,
                                    translation: value.translation.width, width: geometry.size.width,
                                    duration: player.currentItem?.duration.seconds ?? 0) else { return }
                            if dragStart == nil { dragStart = player.currentTime().seconds }
                            dragTarget = target
                        }
                        .onEnded { _ in
                            if let dragTarget {
                                player.seek(to: CMTime(seconds: dragTarget, preferredTimescale: 600))
                            }
                            dragStart = nil
                            dragTarget = nil
                        })
                if locked {
                    HStack {
                        control("解锁", "lock.fill") { locked = false; controls = true }
                        Spacer()
                    }.padding()
                } else if controls {
                    VStack(spacing: 12) {
                        HStack {
                            if expanded { control("关闭全屏", "xmark") { close?() } }
                            Text(title).font(.headline).lineLimit(1)
                            Spacer(minLength: 8)
                            AirPlayControl().frame(width: 36, height: 36)
                            Text("系统解码").font(.caption).fixedSize()
                        }
                        Spacer(minLength: 0)
                        HStack {
                            control("锁定", "lock.open") { locked = true }
                            Spacer()
                            control("静音", muted ? "speaker.slash" : "speaker.wave.2") {
                                muted.toggle()
                                player.isMuted = muted
                            }
                        }
                        Spacer(minLength: 0)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            let duration = valid(player.currentItem?.duration.seconds ?? 0)
                            let current = valid(player.currentTime().seconds)
                            VStack(spacing: 10) {
                                HStack {
                                    Text(clock(dragTarget ?? scrub ?? current)).monospacedDigit()
                                    Slider(value: Binding(get: { min(dragTarget ?? scrub ?? current, max(duration, 1)) },
                                                          set: { scrub = $0 }),
                                           in: 0...max(duration, 1), onEditingChanged: { editing in
                                        if !editing, let scrub {
                                            player.seek(to: CMTime(seconds: scrub, preferredTimescale: 600))
                                            self.scrub = nil
                                        }
                                    }).disabled(duration <= 0)
                                    Text(clock(duration)).monospacedDigit()
                                }.font(.caption)
                                HStack {
                                    control("播放或暂停", player.timeControlStatus == .playing ? "pause.fill" : "play.fill") {
                                        if player.timeControlStatus == .playing { player.pause() }
                                        else { player.playImmediately(atRate: speed) }
                                    }
                                    Spacer()
                                    control("画面比例", fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") {
                                        fill.toggle()
                                    }
                                    Menu {
                                        ForEach([Float(0.5), 1, 1.25, 1.5, 2], id: \.self) { rate in
                                            Button("\(rate.formatted())×") {
                                                speed = rate
                                                if player.timeControlStatus == .playing { player.rate = rate }
                                            }
                                        }
                                    } label: { Text("\(speed.formatted())×").frame(minWidth: 44, minHeight: 36) }
                                    control(expanded ? "退出全屏" : "全屏", "arrow.up.left.and.arrow.down.right.square") {
                                        if expanded { close?() } else { fullscreen = true }
                                    }
                                }
                            }
                        }
                    }
                    .padding(geometry.size.height < 240 ? 12 : 24)
                    .background {
                        LinearGradient(colors: [.black.opacity(0.7), .clear, .black.opacity(0.8)],
                                       startPoint: .top, endPoint: .bottom).allowsHitTesting(false)
                    }
                }
                if let dragTarget {
                    VStack(spacing: 8) {
                        Text(dragTarget >= (dragStart ?? 0) ? "快进" : "快退")
                        Text(clock(dragTarget)).font(.title2.monospacedDigit())
                        Text(String(format: "%+.0f 秒", dragTarget - (dragStart ?? 0)))
                    }
                    .padding(20).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                }
            }.foregroundStyle(.white)
        }
        .fullScreenCover(isPresented: $fullscreen) {
            PlaybackWindow(player: player, title: title, close: { fullscreen = false })
        }
        .onAppear { muted = player.isMuted }
    }

    private func control(_ label: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.title2).frame(width: 44, height: 36) }
            .accessibilityLabel(label)
    }
    private func valid(_ value: Double) -> Double { value.isFinite ? max(value, 0) : 0 }
    private func clock(_ value: Double) -> String {
        let seconds = Int(valid(value))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum PlaybackSeeking {
    static func target(start: Double, translation: Double, width: Double, duration: Double) -> Double? {
        guard start.isFinite, translation.isFinite, width.isFinite, width > 0,
              duration.isFinite, duration > 0 else { return nil }
        // A full-width swipe moves up to two minutes, with finer control for short clips.
        return min(duration, max(0, start + translation / width * min(duration, 120)))
    }
}

struct PlaybackWindow: UIViewControllerRepresentable {
    let player: AVPlayer
    let title: String
    let close: () -> Void
    func makeUIViewController(context: Context) -> LandscapePlayerController {
        LandscapePlayerController(rootView: PlaybackSurface(
            player: player, title: title, expanded: true, close: close))
    }
    func updateUIViewController(_ controller: LandscapePlayerController, context: Context) {}
}

final class LandscapePlayerController: UIHostingController<PlaybackSurface> {
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        PlayerOrientationDelegate.orientations = .landscape
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsUpdateOfSupportedInterfaceOrientations()
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        PlayerOrientationDelegate.orientations = .portrait
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        scene.windows.first(where: \.isKeyWindow)?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let fill: Bool
    func makeUIView(context: Context) -> VideoLayerHost { VideoLayerHost() }
    func updateUIView(_ view: VideoLayerHost, context: Context) {
        view.videoLayer.player = player
        view.videoLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
    }
    static func dismantleUIView(_ view: VideoLayerHost, coordinator: ()) { view.videoLayer.player = nil }
}

private final class VideoLayerHost: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private struct AirPlayControl: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ view: AVRoutePickerView, context: Context) {}
}
