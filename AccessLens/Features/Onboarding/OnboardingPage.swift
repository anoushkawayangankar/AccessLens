import Foundation

enum OnboardingPage: Int, CaseIterable, Hashable, Identifiable {
    case welcome
    case findings
    case privacy
    case cameraPreparation

    var id: Int { rawValue }

    var symbolName: String {
        switch self {
        case .welcome: "accessibility"
        case .findings: "questionmark.circle"
        case .privacy: "hand.raised"
        case .cameraPreparation: "camera"
        }
    }

    var title: String {
        switch self {
        case .welcome: "Welcome to AccessLens"
        case .findings: "What findings mean"
        case .privacy: "Privacy by design"
        case .cameraPreparation: "Camera preparation"
        }
    }

    var summary: String {
        switch self {
        case .welcome:
            "AccessLens is designed to help identify potential accessibility barriers in real-world environments using on-device analysis."
        case .findings:
            "AccessLens observations are assistive indicators that can help you decide what to inspect more closely."
        case .privacy:
            "AccessLens is designed to analyze camera input on your device. Camera frames are not uploaded for analysis."
        case .cameraPreparation:
            "Scanning will require camera access when scanning becomes available. AccessLens will ask only when you begin using that functionality."
        }
    }

    var details: [String] {
        switch self {
        case .welcome:
            [
                "It is an assistive inspection aid, not a compliance authority."
            ]
        case .findings:
            [
                "An observation may be detected, possible, uncertain, or unable to assess.",
                "AccessLens can miss barriers or surface false positives.",
                "It does not certify that an environment is accessible or inaccessible."
            ]
        case .privacy:
            [
                "Core functionality does not require an account.",
                "AccessLens does not include analytics or tracking."
            ]
        case .cameraPreparation:
            [
                "Camera access is not requested during this onboarding.",
                "AccessLens does not provide legal or professional accessibility certification."
            ]
        }
    }
}

