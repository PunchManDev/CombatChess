import SwiftUI
import SpriteKit

// MARK: - Pixel asset helpers (unified Street Fighter-style design language)

/// Nearest-neighbor texture so pixel art stays crisp in SpriteKit.
func pixelTexture(_ name: String) -> SKTexture {
    let texture = SKTexture(imageNamed: name)
    texture.filteringMode = .nearest
    return texture
}

/// Crisp pixel-art image for SwiftUI (no interpolation).
struct PixelImage: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        Image(uiImage: UIImage(named: name) ?? UIImage())
            .resizable()
            .interpolation(.none)
    }
}

extension PieceType {
    /// Sprite frame asset name, e.g. fighter_queen_blue_idle_a.
    func fighterAsset(team: String, frame: String) -> String {
        return "fighter_\(rawValue)_\(team)_\(frame)"
    }

    /// Board icon asset name, e.g. icon_rook_white.
    func iconAsset(for color: PieceColor) -> String {
        return "icon_\(rawValue)_\(color == .white ? "white" : "black")"
    }
}

extension Difficulty {
    /// Fight stage per tier: dojo → rooftop → throne room.
    var stageBackground: String {
        switch self {
        case .easy: return "bg_dojo"
        case .medium: return "bg_rooftop"
        case .hard: return "bg_throne"
        }
    }

    var stageName: String {
        switch self {
        case .easy: return "SUBURBAN DOJO"
        case .medium: return "DUSK ROOFTOP"
        case .hard: return "THRONE ROOM"
        }
    }
}

// MARK: - Arcade UI palette

enum Arcade {
    static let bg = Color(red: 0.09, green: 0.07, blue: 0.13)
    static let panel = Color(red: 0.13, green: 0.10, blue: 0.19)
    static let gold = Color(red: 0.96, green: 0.73, blue: 0.15)
    static let red = Color(red: 0.91, green: 0.26, blue: 0.28)
    static let blue = Color(red: 0.28, green: 0.48, blue: 0.96)
    static let cream = Color(red: 0.96, green: 0.94, blue: 0.90)
}

/// Chunky arcade button: monospaced caps, thick border, press inverts.
struct ArcadeButtonStyle: ButtonStyle {
    var color: Color = Arcade.gold
    var filled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .monospaced).weight(.heavy))
            .textCase(.uppercase)
            .foregroundStyle(configuration.isPressed || filled ? Color.black : color)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed || filled ? color : Color.black.opacity(0.6))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.25)).frame(height: 2)
            }
            .overlay(
                Rectangle().strokeBorder(color, lineWidth: 3)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
    }
}

/// Bordered arcade panel for overlays and cards.
struct ArcadePanel: ViewModifier {
    var border: Color = Arcade.gold

    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Arcade.panel.opacity(0.97))
            .overlay(Rectangle().strokeBorder(border, lineWidth: 3))
            .overlay(Rectangle().strokeBorder(Color.black, lineWidth: 1).padding(3))
    }
}

extension View {
    func arcadePanel(border: Color = Arcade.gold) -> some View {
        return modifier(ArcadePanel(border: border))
    }
}
