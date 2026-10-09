import FirebaseCore
import FirebaseMessaging
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// Same channel name as Android's `MainActivity.kt` and Dart's
  /// `ScreenSecurityService`.
  private var screenSecurityChannel: FlutterMethodChannel?

  /// Opaque black window above everything (alerts, the video surface, any
  /// native view) while the screen is recorded / mirrored / AirPlayed.
  private var captureShieldWindow: UIWindow?

  /// Makes protected screens render black in screenshots / recordings.
  private let screenProtector = ScreenProtector()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Dart also calls `Firebase.initializeApp()`; FlutterFire reuses the
    // default app configured here (from GoogleService-Info.plist).
    // Without the plist in the bundle `configure()` raises an uncaught
    // NSException (instant launch crash) — skip Firebase instead.
    if FirebaseApp.app() == nil {
      if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
        FirebaseApp.configure()
      } else {
        NSLog("[Firebase] GoogleService-Info.plist missing — push disabled")
      }
    }
    // Lets firebase_messaging / flutter_local_notifications present
    // notifications while the app is in the foreground and handle taps.
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    GeneratedPluginRegistrant.register(with: self)
    setUpScreenSecurity()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Hands the APNs token to FCM (needed for an FCM token on iOS), then lets
  /// the plugins see it too.
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    if FirebaseApp.app() != nil {
      Messaging.messaging().apnsToken = deviceToken
    }
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }

  /// iOS can't block screenshots the way Android's FLAG_SECURE does, so the
  /// app detects capture instead: screen recording / mirroring
  /// (`UIScreen.isCaptured`) and screenshots, reported to Dart, which covers
  /// protected content and warns the student.
  private func setUpScreenSecurity() {
    // Through the plugin registrar rather than `window.rootViewController`,
    // which isn't guaranteed to be a FlutterViewController this early.
    guard let registrar = self.registrar(forPlugin: "ScreenSecurity") else { return }
    let channel = FlutterMethodChannel(
      name: "com.itaaleem.app/screen_security",
      binaryMessenger: registrar.messenger()
    )
    screenSecurityChannel = channel

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "isCaptured":
        result(UIScreen.main.isCaptured)
      case "enableSecure", "protectOn":
        self?.screenProtector.protectOn(window: self?.window)
        result(nil)
      case "disableSecure", "protectOff":
        self?.screenProtector.protectOff()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.captureStateChanged()
    }

    // Recording can start/stop while the app is backgrounded — re-check on
    // the way back (and on launch) so the shield is never stale.
    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.captureStateChanged()
    }
    DispatchQueue.main.async { [weak self] in
      self?.captureStateChanged()
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.screenSecurityChannel?.invokeMethod("onScreenshot", arguments: nil)
    }
  }

  private func captureStateChanged() {
    let captured = UIScreen.main.isCaptured
    if captured {
      showCaptureShield()
    } else {
      hideCaptureShield()
    }
    screenSecurityChannel?.invokeMethod("onCaptureChanged", arguments: captured)
  }

  private func showCaptureShield() {
    if captureShieldWindow != nil { return }
    let shield: UIWindow
    if let scene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive })
      ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
      shield = UIWindow(windowScene: scene)
    } else {
      shield = UIWindow(frame: UIScreen.main.bounds)
    }
    shield.windowLevel = UIWindow.Level.alert + 1
    shield.backgroundColor = .black
    shield.rootViewController = CaptureShieldViewController()
    shield.isHidden = false
    captureShieldWindow = shield
  }

  private func hideCaptureShield() {
    captureShieldWindow?.isHidden = true
    captureShieldWindow = nil
  }
}

/// Hides the app's content from screenshots, screen recordings and AirPlay
/// with the secure-text-field trick (as in the `screen_protector` /
/// `no_screenshot` plugins): the window's layer is re-parented into the
/// secure container layer of a hidden `UITextField`. While
/// `isSecureTextEntry` is true iOS draws that container as black in any
/// capture, but normally on the device's own screen. Only layers move — the
/// view hierarchy is untouched, so touches and gestures work as before.
final class ScreenProtector {
  private var field: UITextField?
  private weak var attachedWindow: UIWindow?

  func protectOn(window: UIWindow?) {
    guard let window = window ?? Self.keyWindow() else { return }
    attach(to: window)
    field?.isSecureTextEntry = true
  }

  func protectOff() {
    field?.isSecureTextEntry = false
  }

  private func attach(to window: UIWindow) {
    if field != nil, attachedWindow === window { return }
    guard let superlayer = window.layer.superlayer else { return }
    let field = UITextField()
    field.isSecureTextEntry = false
    field.isUserInteractionEnabled = false
    field.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(field)
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    // The secure container is the first sublayer before iOS 17, the last on
    // 17+.
    superlayer.addSublayer(field.layer)
    let container: CALayer?
    if #available(iOS 17.0, *) {
      container = field.layer.sublayers?.last
    } else {
      container = field.layer.sublayers?.first
    }
    guard let container = container else {
      field.removeFromSuperview()
      return
    }
    container.addSublayer(window.layer)
    self.field = field
    attachedWindow = window
  }

  private static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
  }
}

/// The black screen with the notice, centered, in white.
private final class CaptureShieldViewController: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    let icon = UIImageView(image: UIImage(systemName: "lock.fill"))
    icon.tintColor = .white
    icon.contentMode = .scaleAspectFit
    icon.translatesAutoresizingMaskIntoConstraints = false

    let title = UILabel()
    title.text = "تسجيل الشاشة غير مسموح"
    title.font = UIFont(name: "Cairo-Bold", size: 22) ?? .boldSystemFont(ofSize: 22)
    title.textColor = .white
    title.textAlignment = .center
    title.numberOfLines = 0

    let subtitle = UILabel()
    subtitle.text = "يرجى إيقاف التسجيل للمتابعة"
    subtitle.font = UIFont(name: "Cairo-Regular", size: 16) ?? .systemFont(ofSize: 16)
    subtitle.textColor = UIColor.white.withAlphaComponent(0.75)
    subtitle.textAlignment = .center
    subtitle.numberOfLines = 0

    let stack = UIStackView(arrangedSubviews: [icon, title, subtitle])
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 72),
      icon.heightAnchor.constraint(equalToConstant: 72),
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }
  override var prefersStatusBarHidden: Bool { true }
}
