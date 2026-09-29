import Flutter
import UIKit

/// Small, app-owned bridge. No third-party native rendering dependencies.
final class FursaNativePlugin: NSObject, FlutterPlugin {
  private let feedback = UISelectionFeedbackGenerator()

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "app.fursa/native", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(FursaNativePlugin(), channel: channel)
    registrar.register(
      FursaNavigationFactory(messenger: registrar.messenger()),
      withId: "app.fursa/navigation")
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "selectionHaptic":
      feedback.selectionChanged()
      feedback.prepare()
      result(nil)
    case "symbol":
      guard let arguments = call.arguments as? [String: Any],
        let name = arguments["name"] as? String
      else {
        result(FlutterError(code: "invalid_arguments", message: "Missing symbol name", details: nil))
        return
      }
      let size = min(max((arguments["size"] as? NSNumber)?.doubleValue ?? 24, 8), 128)
      let configuration = UIImage.SymbolConfiguration(pointSize: size, weight: .regular)
      guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else {
        result(nil)
        return
      }
      let value = (arguments["color"] as? NSNumber)?.uint32Value ?? 0xFF20508A
      let color = UIColor(
        red: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: CGFloat((value >> 24) & 0xFF) / 255)
      let tinted = symbol.withTintColor(color, renderingMode: .alwaysOriginal)
      // Rasterize at 3x so the channel result remains sharp on Retina iPhones.
      let format = UIGraphicsImageRendererFormat()
      format.scale = 3
      format.opaque = false
      let renderer = UIGraphicsImageRenderer(size: tinted.size, format: format)
      let image = renderer.image { _ in tinted.draw(at: .zero) }
      result(image.pngData().map { FlutterStandardTypedData(bytes: $0) })
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private final class FursaNavigationFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    let index = ((args as? [String: Any])?["selectedIndex"] as? NSNumber)?.intValue ?? 0
    return FursaNavigationView(
      frame: frame, viewId: viewId, messenger: messenger, selectedIndex: index)
  }
}

/// Owns a real system tab bar, as in Surfa. Selection gestures and Liquid Glass
/// are UIKit's behavior; Flutter receives the logical destination afterwards.
private final class FursaNavigationView: NSObject, FlutterPlatformView, UITabBarDelegate {
  private let navigation: FursaNavigationBar
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger, selectedIndex: Int) {
    navigation = FursaNavigationBar(frame: frame)
    channel = FlutterMethodChannel(
      name: "app.fursa/navigation/\(viewId)", binaryMessenger: messenger)
    super.init()

    navigation.tabBar.delegate = self
    navigation.setSelected(selectedIndex)
    navigation.onHeightChanged = { [weak self] height in
      self?.channel.invokeMethod("onHeightChanged", arguments: height)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "setSelected":
        if let index = call.arguments as? NSNumber {
          self.navigation.setSelected(index.intValue)
        }
        result(nil)
      case "getHeight":
        result(self.navigation.fittedHeight)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { channel.setMethodCallHandler(nil) }

  func view() -> UIView { navigation }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    channel.invokeMethod("onSelected", arguments: item.tag)
  }
}

private final class FursaNavigationBar: UIView {
  let tabBar = UITabBar()
  var onHeightChanged: ((CGFloat) -> Void)?
  private var reportedHeight: CGFloat = 0

  /// Includes UIKit's own bottom safe area. Flutter must not add it twice.
  var fittedHeight: CGFloat {
    guard bounds.width > 0 else { return 0 }
    return tabBar.sizeThatFits(
      CGSize(width: bounds.width, height: .greatestFiniteMagnitude)
    ).height
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .clear
    isOpaque = false
    tabBar.semanticContentAttribute = .forceRightToLeft
    // Dynamic tint keeps the real UIKit bar readable when the system changes
    // appearance while the app is open. UIKit continues to own its glass.
    tabBar.tintColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 149 / 255, green: 195 / 255, blue: 255 / 255, alpha: 1)
        : UIColor(red: 32 / 255, green: 80 / 255, blue: 138 / 255, alpha: 1)
    }
    tabBar.unselectedItemTintColor = UIColor { traits in
      traits.userInterfaceStyle == .dark
        ? UIColor(red: 170 / 255, green: 188 / 255, blue: 211 / 255, alpha: 1)
        : UIColor(red: 18 / 255, green: 35 / 255, blue: 63 / 255, alpha: 1)
    }

    let titles = ["الفرص", "المحفوظة", "أضف فرصة"]
    let symbols = ["house", "heart", "plus"]
    tabBar.items = titles.indices.map { index in
      let image = Self.tabImage(symbols[index])
      let item = UITabBarItem(title: titles[index], image: image, selectedImage: image)
      item.tag = index
      item.accessibilityLabel = titles[index]
      item.accessibilityHint = index == 2 ? "نشر فرصة عمل أو إدارة فرصك" : nil
      return item
    }

    // Leave the iOS 26 appearance untouched so UIKit supplies the actual glass
    // capsule, its animated selection, press-and-slide and native accessibility.
    // Earlier releases retain their own translucent system tab bar appearance.
    // No custom UIButton row, opaque selected pill or private UIKit APIs.
    addSubview(tabBar)
    setSelected(0)
  }

  /// Sanad glyphs generated from the same catalog used by Flutter.
  /// UIKit applies its selected tint and native Liquid Glass interactions.
  private static func tabImage(_ name: String) -> UIImage? {
    guard let path = FursaIconCatalog.path(for: name) else { return nil }
    let size: CGFloat = 22
    return UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { renderer in
      let context = renderer.cgContext
      context.scaleBy(x: size / 24, y: size / 24)
      if let accent = FursaIconCatalog.accent(for: name) {
        context.setFillColor(
          UIColor.black.withAlphaComponent(FursaIconCatalog.accentOpacity).cgColor)
        context.addPath(accent)
        context.fillPath()
      }
      context.setStrokeColor(UIColor.black.cgColor)
      context.setLineWidth(FursaIconCatalog.strokeWidth)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.addPath(path)
      context.strokePath()
    }.withRenderingMode(.alwaysTemplate)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func setSelected(_ index: Int) {
    guard let item = tabBar.items?.first(where: { $0.tag == index }),
      tabBar.selectedItem !== item
    else { return }
    tabBar.selectedItem = item
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    tabBar.frame = bounds
    reportHeight()
  }

  override func safeAreaInsetsDidChange() {
    super.safeAreaInsetsDidChange()
    reportHeight()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    setNeedsLayout()
  }

  private func reportHeight() {
    let height = fittedHeight
    guard height > 0, abs(height - reportedHeight) > 0.5 else { return }
    reportedHeight = height
    onHeightChanged?(height)
  }
}
