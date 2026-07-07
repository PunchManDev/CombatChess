import SpriteKit
import UIKit

// MARK: - Animated pixel fighter

/// Sprite fighter with 12 poses: idle_a/b, wind_l/r, punch_l/r, block_l/r,
/// dodge, hit, exhausted, ko. Drawn facing right; mirrored for the foe.
final class FighterNode: SKSpriteNode {
    private var frames: [String: SKTexture] = [:]

    /// When set (e.g. "block_l", "exhausted"), the resting pose holds this
    /// frame instead of the idle animation.
    var idleOverride: String? {
        didSet { startIdle() }
    }

    init(piece: PieceType, team: String) {
        let allFrames = ["idle_a", "idle_b", "idle_c", "wind_l", "wind_r", "punch_l", "punch_r",
                         "block_l", "block_r", "dodge", "dodge_b", "hit", "exhausted", "ko"]
        var dict: [String: SKTexture] = [:]
        for f in allFrames {
            dict[f] = pixelTexture(piece.fighterAsset(team: team, frame: f))
        }
        frames = dict
        let tex = dict["idle_a"]!
        super.init(texture: tex, color: .clear, size: tex.size())
        anchorPoint = CGPoint(x: 0.5, y: 0)
        startIdle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func startIdle() {
        removeAction(forKey: "pose")
        removeAction(forKey: "idle")
        if let override = idleOverride {
            texture = frames[override]
            return
        }
        // Fighting-stance bob: 4-step cycle through 3 frames.
        let idle = SKAction.repeatForever(SKAction.sequence([
            SKAction.setTexture(frames["idle_a"]!, resize: false),
            SKAction.wait(forDuration: 0.26),
            SKAction.setTexture(frames["idle_c"]!, resize: false),
            SKAction.wait(forDuration: 0.2),
            SKAction.setTexture(frames["idle_b"]!, resize: false),
            SKAction.wait(forDuration: 0.26),
            SKAction.setTexture(frames["idle_c"]!, resize: false),
            SKAction.wait(forDuration: 0.2)
        ]))
        run(idle, withKey: "idle")
    }

    /// Play a multi-frame animation sequence, then return to the resting pose.
    func playSequence(_ sequence: [(frame: String, duration: Double)]) {
        removeAction(forKey: "idle")
        removeAction(forKey: "pose")
        var actions: [SKAction] = []
        for step in sequence {
            actions.append(SKAction.setTexture(frames[step.frame] ?? frames["idle_a"]!, resize: false))
            actions.append(SKAction.wait(forDuration: step.duration))
        }
        actions.append(SKAction.run { [weak self] in self?.startIdle() })
        run(SKAction.sequence(actions), withKey: "pose")
    }

    /// Hold a pose until the next pose change (telegraphs, KO).
    func hold(_ frame: String) {
        removeAction(forKey: "idle")
        removeAction(forKey: "pose")
        texture = frames[frame]
    }

    /// Show a pose briefly, then return to the resting pose.
    func flash(_ frame: String, duration: Double) {
        removeAction(forKey: "idle")
        removeAction(forKey: "pose")
        texture = frames[frame]
        run(SKAction.sequence([
            SKAction.wait(forDuration: duration),
            SKAction.run { [weak self] in self?.startIdle() }
        ]), withKey: "pose")
    }
}

// MARK: - Fight scene: SF2-style button combat with stamina

/// Controls: L/R PUNCH buttons, L/R BLOCK hold-buttons (side-matching),
/// timed DODGE button (full negate + counter meter), ★ star punch.
/// Stamina: punches/blocking/blocked hits drain it; only resting regens it.
/// A fully drained fighter is exhausted: can't act, takes 1.5× damage.
final class FightScene: SKScene {

    private enum Side { case left, right }

    // MARK: Tuning

    private let setup: FightSetup
    private let onEnd: (FightResult) -> Void

    private let fightTimeLimit: Double = 60
    private let lpCooldown: Double = 0.32
    private let rpCooldown: Double = 0.75
    private let dodgeCooldown: Double = 0.55
    private let dodgeWindow: Double = 0.30
    /// After the i-frames end, a whiffed dodge leaves you off-balance.
    private let dodgeVulnDuration: Double = 0.50
    private let mistimedDodgeMult: Double = 1.4
    private let strikeAnimDuration: Double = 0.25
    /// Perfect dodges needed for ★ SUPER (5 on Hard, 3 otherwise).
    private var meterMax: Int { return setup.difficulty.superMeterMax }

    private let staminaMax: Double = 100
    private let lpStamina: Double = 8
    private let rpStamina: Double = 16
    /// Dodging always costs stamina, hit or whiffed.
    private let dodgeStamina: Double = 8
    // Anti-spam: rapid inputs build heat, multiplying stamina costs.
    private let spamGap: Double = 0.45
    private let spamHeatMax: Double = 6
    private let spamCostFactor: Double = 0.35
    private let spamDecayPerSec: Double = 1.1
    private let blockHoldDrain: Double = 7      // per second
    private let blockedHitDrainFactor: Double = 0.3
    private let staminaRegen: Double = 14       // per second
    private let exhaustRecoverAt: Double = 30
    private let exhaustDamageMult: Double = 1.5
    private let correctBlockMult: Double = 0.2
    private let wrongBlockMult: Double = 0.55

    // MARK: Fight state

    private var playerHP: Double
    private var aiHP: Double
    private let playerMaxHP: Double
    private let aiMaxHP: Double
    private var playerStamina: Double = 100
    private var aiStamina: Double = 100
    private var playerExhausted = false
    private var aiExhausted = false

    private var elapsed: Double = 0
    private var lastUpdateTime: TimeInterval = 0
    private var ended = false
    private var introActive = true

    private enum OpponentState { case idle, telegraph, strike, recover, exhausted }
    private var oppState: OpponentState = .idle
    private var stateUntil: Double = 0
    private var incomingIsHeavy = false
    private var incomingSide: Side = .left

    private var punchReadyAt: Double = 0
    private var dodgeReadyAt: Double = 0
    private var dodgingUntil: Double = -1
    private var dodgeVulnUntil: Double = -1     // mistimed-dodge punish window
    private var playerRestingAt: Double = 0     // no regen until this time
    private var aiRestingAt: Double = 0
    private var meter = 0
    private var spamHeat: Double = 0
    private var lastPressAt: Double = -10

    private var blockTouches: [UITouch: Side] = [:]
    private var playerBlockSide: Side?

    /// Deterministic RNG for all game-affecting rolls (seeded per fight;
    /// online clients share the seed — docs/ONLINE_MULTIPLAYER.md §2).
    private var rng: SplitMix64

    // MARK: Nodes

    private var playerNode: FighterNode!
    private var aiNode: FighterNode!
    private let playerHPFill = SKSpriteNode(color: SKColor(red: 1.0, green: 0.82, blue: 0.15, alpha: 1), size: .zero)
    private let aiHPFill = SKSpriteNode(color: SKColor(red: 1.0, green: 0.82, blue: 0.15, alpha: 1), size: .zero)
    private let playerStamFill = SKSpriteNode(color: SKColor(red: 0.25, green: 0.9, blue: 0.7, alpha: 1), size: .zero)
    private let aiStamFill = SKSpriteNode(color: SKColor(red: 0.25, green: 0.9, blue: 0.7, alpha: 1), size: .zero)
    private let timerLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let meterPips = SKNode()
    private let statusLabel = SKLabelNode(fontNamed: "Menlo-Bold")
    private let sideIndicator = SKLabelNode(fontNamed: "Menlo-Bold")
    private var buttons: [String: SKShapeNode] = [:]
    private var groundY: CGFloat = 0
    private var fighterScale: CGFloat = 1
    private var barWidth: CGFloat = 0

    // MARK: Init

    init(size: CGSize, setup: FightSetup, onEnd: @escaping (FightResult) -> Void) {
        self.setup = setup
        self.onEnd = onEnd
        self.rng = SplitMix64(seed: setup.fightSeed)
        self.playerHP = Double(setup.playerPiece.currentHP)
        self.aiHP = Double(setup.aiPiece.currentHP)
        self.playerMaxHP = Double(setup.playerPiece.maxHP)
        self.aiMaxHP = Double(setup.aiPiece.maxHP)
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.08, green: 0.07, blue: 0.12, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Scene setup

    override func didMove(to view: SKView) {
        let w = size.width
        let h = size.height
        groundY = h * 0.30
        fighterScale = (h * 0.36) / 96.0

        let bgTexture = pixelTexture(setup.difficulty.stageBackground)
        let bg = SKSpriteNode(texture: bgTexture)
        let bgScale = max(w / bgTexture.size().width, h / bgTexture.size().height)
        bg.setScale(bgScale)
        bg.position = CGPoint(x: w / 2, y: h / 2 + h * 0.06)
        bg.zPosition = -10
        addChild(bg)

        playerNode = FighterNode(piece: setup.playerPiece.type,
                                 team: setup.playerPiece.color.teamName)
        playerNode.position = CGPoint(x: w * 0.27, y: groundY)
        playerNode.setScale(fighterScale)
        playerNode.zPosition = 2
        addChild(playerNode)

        aiNode = FighterNode(piece: setup.aiPiece.type,
                             team: setup.aiPiece.color.teamName)
        aiNode.position = CGPoint(x: w * 0.73, y: groundY)
        aiNode.xScale = -fighterScale
        aiNode.yScale = fighterScale
        aiNode.zPosition = 1
        addChild(aiNode)

        for x in [w * 0.27, w * 0.73] {
            let shadow = SKShapeNode(ellipseOf: CGSize(width: 92, height: 16))
            shadow.fillColor = SKColor(white: 0, alpha: 0.35)
            shadow.strokeColor = .clear
            shadow.position = CGPoint(x: x, y: groundY - 2)
            shadow.zPosition = 0
            addChild(shadow)
        }

        buildHUD(w: w, h: h)
        buildControlDeck(w: w)
        runIntro(w: w, h: h)
    }

    // MARK: HUD

    private func buildHUD(w: CGFloat, h: CGFloat) {
        let barY = h - 76
        barWidth = w * 0.36
        let barHeight: CGFloat = 15

        let header = SKSpriteNode(color: SKColor(white: 0, alpha: 0.45),
                                  size: CGSize(width: w, height: 104))
        header.position = CGPoint(x: w / 2, y: h - 52)
        header.zPosition = 5
        addChild(header)

        func buildBars(x: CGFloat, hpFill: SKSpriteNode, stamFill: SKSpriteNode,
                       rightAligned: Bool, label: String) {
            let anchor = CGPoint(x: rightAligned ? 1 : 0, y: 0.5)

            let hpBack = SKSpriteNode(color: SKColor(red: 0.55, green: 0.09, blue: 0.10, alpha: 1),
                                      size: CGSize(width: barWidth, height: barHeight))
            hpBack.anchorPoint = anchor
            hpBack.position = CGPoint(x: x, y: barY)
            hpBack.zPosition = 6
            addChild(hpBack)

            hpFill.size = CGSize(width: barWidth, height: barHeight)
            hpFill.anchorPoint = anchor
            hpFill.position = CGPoint(x: x, y: barY)
            hpFill.zPosition = 7
            addChild(hpFill)

            let border = SKShapeNode(rect: CGRect(x: rightAligned ? x - barWidth : x,
                                                  y: barY - barHeight / 2,
                                                  width: barWidth, height: barHeight))
            border.strokeColor = SKColor(white: 0.95, alpha: 1)
            border.lineWidth = 2
            border.zPosition = 8
            addChild(border)

            // Stamina bar below HP
            let stamBack = SKSpriteNode(color: SKColor(white: 0.16, alpha: 1),
                                        size: CGSize(width: barWidth, height: 7))
            stamBack.anchorPoint = anchor
            stamBack.position = CGPoint(x: x, y: barY - 15)
            stamBack.zPosition = 6
            addChild(stamBack)

            stamFill.size = CGSize(width: barWidth, height: 7)
            stamFill.anchorPoint = anchor
            stamFill.position = CGPoint(x: x, y: barY - 15)
            stamFill.zPosition = 7
            addChild(stamFill)

            let name = SKLabelNode(fontNamed: "Menlo-Bold")
            name.text = label
            name.fontSize = 11
            name.fontColor = SKColor(white: 0.95, alpha: 1)
            name.horizontalAlignmentMode = rightAligned ? .right : .left
            name.position = CGPoint(x: x, y: barY - 36)
            name.zPosition = 8
            addChild(name)
        }

        buildBars(x: 14, hpFill: playerHPFill, stamFill: playerStamFill,
                  rightAligned: false,
                  label: "YOU·\(setup.playerPiece.type.displayName.uppercased())")
        buildBars(x: w - 14, hpFill: aiHPFill, stamFill: aiStamFill,
                  rightAligned: true,
                  label: "FOE·\(setup.aiPiece.type.displayName.uppercased())")
        updateBars()

        let timerBox = SKShapeNode(rect: CGRect(x: w / 2 - 26, y: barY - 20, width: 52, height: 40))
        timerBox.fillColor = SKColor(white: 0, alpha: 0.7)
        timerBox.strokeColor = SKColor(red: 0.96, green: 0.73, blue: 0.15, alpha: 1)
        timerBox.lineWidth = 2
        timerBox.zPosition = 8
        addChild(timerBox)

        timerLabel.fontSize = 26
        timerLabel.fontColor = .white
        timerLabel.verticalAlignmentMode = .center
        timerLabel.position = CGPoint(x: w / 2, y: barY)
        timerLabel.zPosition = 9
        timerLabel.text = "60"
        addChild(timerLabel)

        meterPips.position = CGPoint(x: 14, y: barY - 52)
        meterPips.zPosition = 8
        addChild(meterPips)
        updateMeterPips()

        statusLabel.fontSize = 22
        statusLabel.fontColor = .white
        statusLabel.position = CGPoint(x: w / 2, y: h * 0.60)
        statusLabel.zPosition = 15
        statusLabel.alpha = 0
        addChild(statusLabel)

        // Incoming-attack side cue above the foe
        sideIndicator.fontSize = 18
        sideIndicator.fontColor = .cyan
        sideIndicator.position = CGPoint(x: w * 0.73, y: groundY + 96 * fighterScale + 12)
        sideIndicator.zPosition = 15
        sideIndicator.alpha = 0
        addChild(sideIndicator)

        let stage = SKLabelNode(fontNamed: "Menlo-Bold")
        stage.text = setup.difficulty.stageName
        stage.fontSize = 10
        stage.fontColor = SKColor(white: 1, alpha: 0.5)
        stage.position = CGPoint(x: w / 2, y: h - 116)
        stage.zPosition = 8
        addChild(stage)
    }

    // MARK: Control deck (SF2-style buttons)

    private func buildControlDeck(w: CGFloat) {
        let deck = SKSpriteNode(color: SKColor(white: 0, alpha: 0.5),
                                size: CGSize(width: w, height: 204))
        deck.position = CGPoint(x: w / 2, y: 102)
        deck.zPosition = 9
        addChild(deck)

        let punchColor = SKColor(red: 0.62, green: 0.16, blue: 0.16, alpha: 0.95)
        let punchBorder = SKColor(red: 1.0, green: 0.45, blue: 0.4, alpha: 1)
        let blockColor = SKColor(red: 0.13, green: 0.22, blue: 0.5, alpha: 0.95)
        let blockBorder = SKColor(red: 0.45, green: 0.65, blue: 1.0, alpha: 1)
        let dodgeColor = SKColor(red: 0.1, green: 0.4, blue: 0.28, alpha: 0.95)
        let dodgeBorder = SKColor(red: 0.35, green: 0.95, blue: 0.6, alpha: 1)
        let starColor = SKColor(red: 0.75, green: 0.55, blue: 0.05, alpha: 0.95)
        let starBorder = SKColor(red: 1.0, green: 0.85, blue: 0.3, alpha: 1)

        // Layout: punches on top (L left / R right), blocks directly beneath
        // them, and a full-width DODGE bar underneath everything.
        let sideWidth = min(150, w * 0.42)
        let sideX = 14 + sideWidth / 2

        addButton(name: "lp", text: "L PUNCH", size: CGSize(width: sideWidth, height: 56),
                  color: punchColor, border: punchBorder, position: CGPoint(x: sideX, y: 168))
        addButton(name: "lb", text: "L BLOCK", size: CGSize(width: sideWidth, height: 56),
                  color: blockColor, border: blockBorder, position: CGPoint(x: sideX, y: 106))
        addButton(name: "rp", text: "R PUNCH", size: CGSize(width: sideWidth, height: 56),
                  color: punchColor, border: punchBorder, position: CGPoint(x: w - sideX, y: 168))
        addButton(name: "rb", text: "R BLOCK", size: CGSize(width: sideWidth, height: 56),
                  color: blockColor, border: blockBorder, position: CGPoint(x: w - sideX, y: 106))
        addButton(name: "dodge", text: "DODGE", size: CGSize(width: w - 24, height: 54),
                  color: dodgeColor, border: dodgeBorder, position: CGPoint(x: w / 2, y: 43))
        // Star punch floats above the deck when earned.
        addButton(name: "star", text: "★ SUPER", size: CGSize(width: 132, height: 54),
                  color: starColor, border: starBorder, position: CGPoint(x: w / 2, y: 232))
        buttons["star"]?.isHidden = true

        let hint = SKLabelNode(fontNamed: "Menlo-Bold")
        hint.text = "HOLD BLOCK · TIME YOUR DODGE"
        hint.fontSize = 9
        hint.fontColor = SKColor(white: 0.65, alpha: 1)
        hint.position = CGPoint(x: w / 2, y: 6)
        hint.zPosition = 10
        addChild(hint)
    }

    private func addButton(name: String, text: String, size btnSize: CGSize,
                           color: SKColor, border: SKColor, position: CGPoint) {
        let button = SKShapeNode(rect: CGRect(x: -btnSize.width / 2, y: -btnSize.height / 2,
                                              width: btnSize.width, height: btnSize.height))
        button.fillColor = color
        button.strokeColor = border
        button.lineWidth = 3
        button.position = position
        button.zPosition = 10
        button.name = name
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = text
        label.fontSize = 13
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.name = name
        button.addChild(label)
        addChild(button)
        buttons[name] = button
    }

    private func flashButton(_ name: String) {
        guard let button = buttons[name] else { return }
        let original = button.fillColor
        button.fillColor = SKColor(white: 0.85, alpha: 1)
        button.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.09),
            SKAction.run { button.fillColor = original }
        ]))
    }

    private func runIntro(w: CGFloat, h: CGFloat) {
        introActive = true
        let fight = SKSpriteNode(texture: pixelTexture("text_fight"))
        fight.setScale(2.4)
        fight.position = CGPoint(x: w / 2, y: h * 0.55)
        fight.zPosition = 30
        fight.alpha = 0
        addChild(fight)
        fight.run(SKAction.sequence([
            SKAction.group([SKAction.fadeIn(withDuration: 0.15),
                            SKAction.scale(to: 2.9, duration: 0.15)]),
            SKAction.wait(forDuration: 0.7),
            SKAction.fadeOut(withDuration: 0.2),
            SKAction.removeFromParent(),
            SKAction.run { [weak self] in
                guard let self = self else { return }
                self.introActive = false
                self.scheduleIdle()
            }
        ]))
        Haptics.impact(.heavy)
    }

    // MARK: Opponent state machine

    private func scheduleIdle() {
        oppState = .idle
        stateUntil = elapsed + Double.random(in: setup.difficulty.idleRange, using: &rng)
        aiNode.run(SKAction.colorize(withColorBlendFactor: 0, duration: 0.1))
        refreshAIBasePose()
    }

    private func startTelegraph() {
        // AI stamina discipline: rest instead of attacking when low.
        incomingIsHeavy = Double.random(in: 0..<1, using: &rng) < setup.difficulty.aiHeavyChance
        let cost = incomingIsHeavy ? rpStamina : lpStamina
        guard aiStamina >= cost + setup.difficulty.aiStaminaFloor else {
            oppState = .idle
            stateUntil = elapsed + 0.6
            return
        }
        aiStamina -= cost
        aiRestingAt = elapsed + 0.6
        // Light attacks come at your LEFT (block L); heavies at your RIGHT (block R).
        incomingSide = incomingIsHeavy ? .right : .left

        oppState = .telegraph
        let duration = setup.difficulty.telegraphDuration * (incomingIsHeavy ? 1.35 : 1.0)
        stateUntil = elapsed + duration
        aiNode.hold(incomingIsHeavy ? "wind_r" : "wind_l")

        let tint: SKColor = incomingIsHeavy
            ? SKColor(red: 1.0, green: 0.55, blue: 0.1, alpha: 1)
            : SKColor(white: 1.0, alpha: 1)
        aiNode.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.colorize(with: tint, colorBlendFactor: 0.5, duration: 0.09),
            SKAction.colorize(withColorBlendFactor: 0, duration: 0.09)
        ])), withKey: "flash")

        sideIndicator.text = incomingIsHeavy ? "HEAVY ▶ R" : "L ◀ LIGHT"
        sideIndicator.fontColor = incomingIsHeavy
            ? SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1) : .cyan
        sideIndicator.alpha = 1
        Haptics.impact(.light)
    }

    private func resolveOpponentStrike() {
        oppState = .strike
        stateUntil = elapsed + strikeAnimDuration
        aiNode.removeAction(forKey: "flash")
        aiNode.run(SKAction.colorize(withColorBlendFactor: 0, duration: 0.05))
        sideIndicator.run(SKAction.fadeOut(withDuration: 0.2))
        aiNode.flash(incomingIsHeavy ? "punch_r" : "punch_l", duration: strikeAnimDuration + 0.1)
        let lunge: CGFloat = incomingIsHeavy ? 58 : 36
        aiNode.run(SKAction.sequence([
            SKAction.moveBy(x: -lunge, y: 0, duration: 0.08),
            SKAction.moveBy(x: lunge, y: 0, duration: 0.16)
        ]))

        let base = Double(incomingIsHeavy ? setup.aiPiece.type.heavyDamage
                                          : setup.aiPiece.type.jabDamage)

        // Timed dodge: full negation + meter.
        if elapsed < dodgingUntil {
            meter = min(meterMax, meter + 1)
            updateMeterPips()
            buttons["star"]?.isHidden = meter < meterMax
            flashStatus("PERFECT DODGE!", color: .cyan)
            return
        }

        var damage = base
        var blocked = false
        if let side = playerBlockSide {
            blocked = true
            let correct = side == incomingSide
            damage *= correct ? correctBlockMult : wrongBlockMult
            drainPlayerStamina(base * blockedHitDrainFactor)
            flashStatus(correct ? "BLOCKED" : "WRONG SIDE!",
                        color: correct ? SKColor(white: 0.85, alpha: 1)
                                       : SKColor(red: 1.0, green: 0.6, blue: 0.2, alpha: 1))
        } else if elapsed < dodgeVulnUntil {
            // Whiffed dodge: caught off-balance for extra damage.
            damage *= mistimedDodgeMult
            flashStatus("MISTIMED DODGE!", color: SKColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1))
        } else {
            flashStatus(incomingIsHeavy ? "HEAVY HIT!" : "HIT", color: .red)
        }
        if playerExhausted {
            damage *= exhaustDamageMult
        }
        applyDamageToPlayer(damage, blocked: blocked)
    }

    private func startRecover() {
        oppState = .recover
        stateUntil = elapsed + setup.difficulty.aiRecoverDuration
        aiNode.hold("hit")
        aiNode.run(SKAction.colorize(with: SKColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1),
                                     colorBlendFactor: 0.35, duration: 0.1))
    }

    private func refreshAIBasePose() {
        if oppState == .exhausted {
            aiNode.idleOverride = "exhausted"
        } else {
            aiNode.idleOverride = nil
        }
    }

    // MARK: Stamina

    private func drainPlayerStamina(_ amount: Double) {
        playerStamina = max(0, playerStamina - amount)
        if playerStamina <= 0 && !playerExhausted {
            playerExhausted = true
            blockTouches.removeAll()
            playerBlockSide = nil
            flashStatus("EXHAUSTED!", color: SKColor(red: 1.0, green: 0.5, blue: 0.3, alpha: 1))
            Haptics.error()
            refreshPlayerBasePose()
        }
    }

    private func drainAIStamina(_ amount: Double) {
        aiStamina = max(0, aiStamina - amount)
        if aiStamina <= 0 && oppState != .exhausted {
            oppState = .exhausted
            aiNode.removeAction(forKey: "flash")
            aiNode.run(SKAction.colorize(withColorBlendFactor: 0, duration: 0.1))
            sideIndicator.alpha = 0
            flashStatus("FOE EXHAUSTED!", color: SKColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1))
            refreshAIBasePose()
        }
    }

    private func refreshPlayerBasePose() {
        if playerExhausted {
            playerNode.idleOverride = "exhausted"
        } else if playerBlockSide == .left {
            playerNode.idleOverride = "block_l"
        } else if playerBlockSide == .right {
            playerNode.idleOverride = "block_r"
        } else {
            playerNode.idleOverride = nil
        }
    }

    // MARK: Player actions

    private func canAct() -> Bool {
        return !ended && !introActive && !playerExhausted
    }

    /// Anti-spam: every input press builds heat when hammered; heat multiplies
    /// stamina costs so button-mashing burns you out fast.
    private func registerPress() -> Double {
        if elapsed - lastPressAt < spamGap {
            spamHeat = min(spamHeatMax, spamHeat + 1)
        }
        lastPressAt = elapsed
        let mult = 1.0 + spamCostFactor * spamHeat
        if spamHeat >= 3.5 {
            flashStatus("WILD SWINGS!", color: SKColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 1))
        }
        return mult
    }

    private func playerPunch(side: Side) {
        guard canAct(), playerBlockSide == nil, elapsed >= punchReadyAt else { return }
        let isRP = side == .right
        let costMult = registerPress()
        let cost = (isRP ? rpStamina : lpStamina) * costMult
        guard playerStamina > 0 else { return }
        punchReadyAt = elapsed + (isRP ? rpCooldown : lpCooldown)
        playerRestingAt = elapsed + 0.6
        drainPlayerStamina(cost)

        if isRP {
            // Rear cross: brief wind-up, then the hit lands.
            playerNode.flash("wind_r", duration: 0.12)
            run(SKAction.sequence([
                SKAction.wait(forDuration: 0.12),
                SKAction.run { [weak self] in self?.landPlayerPunch(isRP: true) }
            ]))
        } else {
            landPlayerPunch(isRP: false)
        }
    }

    private func landPlayerPunch(isRP: Bool) {
        guard !ended else { return }
        // Multi-frame swing: quick anticipation, then full extension.
        if isRP {
            playerNode.playSequence([("punch_r", 0.24)])
        } else {
            playerNode.playSequence([("wind_l", 0.06), ("punch_l", 0.16)])
        }
        let lunge: CGFloat = isRP ? 46 : 28
        playerNode.run(SKAction.sequence([
            SKAction.moveBy(x: lunge, y: 0, duration: 0.07),
            SKAction.moveBy(x: -lunge, y: 0, duration: 0.12)
        ]))

        var damage = Double(isRP ? setup.playerPiece.type.heavyDamage
                                 : setup.playerPiece.type.jabDamage)
        let aiVulnerable = oppState == .recover || oppState == .exhausted

        if !aiVulnerable {
            if isRP && Double.random(in: 0..<1, using: &rng) < setup.difficulty.aiDodgeChance {
                aiNode.playSequence([("dodge", 0.1), ("dodge_b", 0.18), ("dodge", 0.1)])
                aiNode.run(SKAction.sequence([
                    SKAction.moveBy(x: 32, y: 0, duration: 0.1),
                    SKAction.moveBy(x: -32, y: 0, duration: 0.15)
                ]))
                flashStatus("MISS", color: SKColor(white: 0.6, alpha: 1))
                return
            }
            if oppState == .idle && Double.random(in: 0..<1, using: &rng) < setup.difficulty.aiBlockChance {
                let correct = Double.random(in: 0..<1, using: &rng) < setup.difficulty.aiCorrectSideChance
                let matchingFrame = isRP ? "block_r" : "block_l"
                let wrongFrame = isRP ? "block_l" : "block_r"
                aiNode.flash(correct ? matchingFrame : wrongFrame, duration: 0.3)
                damage *= correct ? correctBlockMult : wrongBlockMult
                drainAIStamina(damage > 0 ? Double(isRP ? setup.playerPiece.type.heavyDamage
                                                        : setup.playerPiece.type.jabDamage) * blockedHitDrainFactor : 0)
                flashStatus(correct ? "GUARDED" : "CHIP!", color: SKColor(white: 0.6, alpha: 1))
            }
        }
        if oppState == .exhausted {
            damage *= exhaustDamageMult
        }
        applyDamageToAI(damage)
    }

    private func playerDodge() {
        guard canAct(), elapsed >= dodgeReadyAt else { return }
        let costMult = registerPress()
        dodgeReadyAt = elapsed + dodgeCooldown
        dodgingUntil = elapsed + dodgeWindow
        dodgeVulnUntil = dodgingUntil + dodgeVulnDuration
        // Dodging always costs stamina, whether or not it connects.
        drainPlayerStamina(dodgeStamina * costMult)
        // Two-stage sway: lean → deep lean → recover.
        playerNode.playSequence([("dodge", 0.10), ("dodge_b", 0.22), ("dodge", 0.12)])
        playerNode.run(SKAction.sequence([
            SKAction.moveBy(x: -40, y: 0, duration: 0.10),
            SKAction.wait(forDuration: 0.14),
            SKAction.moveBy(x: 40, y: 0, duration: 0.12)
        ]))
    }

    private func starPunch() {
        guard canAct(), meter >= meterMax else { return }
        meter = 0
        updateMeterPips()
        buttons["star"]?.isHidden = true
        playerRestingAt = elapsed + 0.6
        playerNode.flash("punch_r", duration: 0.3)
        playerNode.run(SKAction.sequence([
            SKAction.moveBy(x: 62, y: 0, duration: 0.08),
            SKAction.moveBy(x: -62, y: 0, duration: 0.16)
        ]))
        flashStatus("STAR PUNCH!", color: SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1))
        Haptics.impact(.heavy)
        var damage = Double(setup.playerPiece.type.heavyDamage) * 2.5
        if oppState == .exhausted {
            damage *= exhaustDamageMult
        }
        applyDamageToAI(damage)
    }

    // MARK: Damage & effects

    private func hitSpark(at position: CGPoint) {
        let spark = SKLabelNode(fontNamed: "Menlo-Bold")
        spark.text = "✦"
        spark.fontSize = 34
        spark.fontColor = .white
        spark.position = position
        spark.zPosition = 20
        addChild(spark)
        spark.run(SKAction.sequence([
            SKAction.group([SKAction.scale(to: 1.8, duration: 0.12),
                            SKAction.fadeOut(withDuration: 0.16)]),
            SKAction.removeFromParent()
        ]))
    }

    private func applyDamageToAI(_ damage: Double) {
        guard !ended else { return }
        aiHP = max(0, aiHP - damage)
        updateBars()
        let impact = CGPoint(x: aiNode.position.x - 30, y: groundY + 96 * fighterScale * 0.55)
        hitSpark(at: impact)
        popDamage(Int(damage.rounded()), at: impact,
                  color: SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1))
        if aiHP > 0 && (oppState == .idle || oppState == .exhausted) {
            aiNode.flash("hit", duration: 0.2)
        }
        aiNode.run(SKAction.sequence([
            SKAction.moveBy(x: 14, y: 0, duration: 0.05),
            SKAction.moveBy(x: -14, y: 0, duration: 0.07)
        ]))
        Haptics.impact(.medium)
        Haptics.hitSound()
        if aiHP <= 0 {
            finish(playerWon: true)
        }
    }

    private func applyDamageToPlayer(_ damage: Double, blocked: Bool) {
        guard !ended else { return }
        playerHP = max(0, playerHP - damage)
        updateBars()
        let impact = CGPoint(x: playerNode.position.x + 30, y: groundY + 96 * fighterScale * 0.55)
        hitSpark(at: impact)
        popDamage(Int(damage.rounded()), at: impact, color: .red)
        if playerHP > 0 && !blocked {
            playerNode.flash("hit", duration: 0.25)
            playerNode.run(SKAction.sequence([
                SKAction.moveBy(x: -16, y: 0, duration: 0.05),
                SKAction.moveBy(x: 16, y: 0, duration: 0.09)
            ]))
        }
        Haptics.impact(.heavy)
        Haptics.hitSound()
        if playerHP <= 0 {
            finish(playerWon: false)
        }
    }

    private func popDamage(_ amount: Int, at position: CGPoint, color: SKColor) {
        guard amount > 0 else { return }
        let label = SKLabelNode(fontNamed: "Menlo-Bold")
        label.text = "-\(amount)"
        label.fontSize = 24
        label.fontColor = color
        label.position = CGPoint(x: position.x + CGFloat.random(in: -16...16), y: position.y + 26)
        label.zPosition = 20
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([SKAction.moveBy(x: 0, y: 44, duration: 0.6),
                            SKAction.fadeOut(withDuration: 0.6)]),
            SKAction.removeFromParent()
        ]))
    }

    private func flashStatus(_ text: String, color: SKColor) {
        statusLabel.removeAllActions()
        statusLabel.text = text
        statusLabel.fontColor = color
        statusLabel.alpha = 1
        statusLabel.setScale(1.15)
        statusLabel.run(SKAction.sequence([
            SKAction.scale(to: 1.0, duration: 0.08),
            SKAction.wait(forDuration: 0.45),
            SKAction.fadeOut(withDuration: 0.25)
        ]))
    }

    private func updateBars() {
        playerHPFill.xScale = CGFloat(max(0, playerHP / playerMaxHP))
        aiHPFill.xScale = CGFloat(max(0, aiHP / aiMaxHP))
        playerStamFill.xScale = CGFloat(max(0, playerStamina / staminaMax))
        aiStamFill.xScale = CGFloat(max(0, aiStamina / staminaMax))
        playerStamFill.color = playerExhausted
            ? SKColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1)
            : SKColor(red: 0.25, green: 0.9, blue: 0.7, alpha: 1)
        aiStamFill.color = oppState == .exhausted
            ? SKColor(red: 1.0, green: 0.35, blue: 0.25, alpha: 1)
            : SKColor(red: 0.25, green: 0.9, blue: 0.7, alpha: 1)
    }

    private func updateMeterPips() {
        meterPips.removeAllChildren()
        for i in 0..<meterMax {
            let pip = SKShapeNode(rect: CGRect(x: CGFloat(i) * 18, y: 0, width: 12, height: 12))
            pip.fillColor = i < meter
                ? SKColor(red: 1.0, green: 0.85, blue: 0.2, alpha: 1)
                : SKColor(white: 0.2, alpha: 0.9)
            pip.strokeColor = SKColor(white: 0.85, alpha: 1)
            pip.lineWidth = 1.5
            meterPips.addChild(pip)
        }
    }

    // MARK: End of fight

    private func finish(playerWon: Bool) {
        guard !ended else { return }
        ended = true
        blockTouches.removeAll()
        playerBlockSide = nil
        let result = FightResult(playerWon: playerWon,
                                 playerHP: Int(playerHP.rounded()),
                                 aiHP: Int(aiHP.rounded()),
                                 durationSec: elapsed)

        let loser: FighterNode = playerWon ? aiNode : playerNode
        loser.idleOverride = "ko"
        loser.hold("ko")
        loser.run(SKAction.sequence([
            SKAction.moveBy(x: 0, y: 24, duration: 0.12),
            SKAction.moveBy(x: 0, y: -24, duration: 0.16)
        ]))

        let ko = SKSpriteNode(texture: pixelTexture("text_ko"))
        ko.setScale(0.5)
        ko.position = CGPoint(x: size.width / 2, y: size.height * 0.58)
        ko.zPosition = 30
        addChild(ko)
        ko.run(SKAction.scale(to: 2.6, duration: 0.22))

        let verdict = SKLabelNode(fontNamed: "Menlo-Bold")
        verdict.text = playerWon ? "YOU WIN" : "YOU LOSE"
        verdict.fontSize = 24
        verdict.fontColor = playerWon
            ? SKColor(red: 0.4, green: 1.0, blue: 0.5, alpha: 1)
            : SKColor(red: 1.0, green: 0.4, blue: 0.4, alpha: 1)
        verdict.position = CGPoint(x: size.width / 2, y: size.height * 0.48)
        verdict.zPosition = 30
        addChild(verdict)

        Haptics.success()
        run(SKAction.sequence([
            SKAction.wait(forDuration: 1.3),
            SKAction.run { [weak self] in self?.onEnd(result) }
        ]))
    }

    /// Timeout: higher HP percentage wins; ties go to the attacker (PRD §2.4).
    private func resolveTimeout() {
        guard !ended else { return }
        let playerFrac = playerHP / playerMaxHP
        let aiFrac = aiHP / aiMaxHP
        let playerWon: Bool
        if abs(playerFrac - aiFrac) < 0.0001 {
            playerWon = setup.playerIsAttacker
        } else {
            playerWon = playerFrac > aiFrac
        }
        if playerWon {
            aiHP = 0
        } else {
            playerHP = 0
        }
        updateBars()
        finish(playerWon: playerWon)
    }

    // MARK: Update loop

    override func update(_ currentTime: TimeInterval) {
        guard !ended else { return }
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
        }
        let dt = min(currentTime - lastUpdateTime, 0.1)
        lastUpdateTime = currentTime
        guard !introActive else { return }
        elapsed += dt

        // ---- timer
        let remaining = max(0, fightTimeLimit - elapsed)
        timerLabel.text = String(Int(remaining.rounded(.up)))
        timerLabel.fontColor = remaining < 10 ? .red : .white
        if remaining <= 0 {
            resolveTimeout()
            return
        }

        // ---- spam heat cools off over time
        spamHeat = max(0, spamHeat - spamDecayPerSec * dt)

        // ---- player stamina: block drain / passive regen
        if playerBlockSide != nil {
            // Toggling blocks rapidly (heat) makes holding them costlier too.
            drainPlayerStamina(blockHoldDrain * (1.0 + 0.25 * spamHeat) * dt)
        } else if !playerExhausted {
            if elapsed >= playerRestingAt && elapsed >= dodgingUntil {
                playerStamina = min(staminaMax, playerStamina + staminaRegen * dt)
            }
        } else {
            // Exhausted: recover to threshold, then back in the fight.
            playerStamina = min(staminaMax, playerStamina + staminaRegen * dt)
            if playerStamina >= exhaustRecoverAt {
                playerExhausted = false
                flashStatus("RECOVERED", color: SKColor(red: 0.4, green: 1.0, blue: 0.6, alpha: 1))
                refreshPlayerBasePose()
            }
        }

        // ---- AI stamina regen
        if oppState == .idle && elapsed >= aiRestingAt {
            aiStamina = min(staminaMax, aiStamina + staminaRegen * dt)
        } else if oppState == .exhausted {
            aiStamina = min(staminaMax, aiStamina + staminaRegen * dt)
            if aiStamina >= exhaustRecoverAt {
                scheduleIdle()
            }
        }
        updateBars()

        // ---- AI state machine
        if oppState != .exhausted, elapsed >= stateUntil {
            switch oppState {
            case .idle:
                startTelegraph()
            case .telegraph:
                resolveOpponentStrike()
            case .strike:
                startRecover()
            case .recover:
                scheduleIdle()
            case .exhausted:
                break
            }
        }
    }

    // MARK: Touch handling

    private func buttonName(at location: CGPoint) -> String? {
        for node in nodes(at: location) {
            if let name = node.name, buttons.keys.contains(name) {
                return name
            }
        }
        return nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self)
            guard let name = buttonName(at: location) else { continue }
            switch name {
            case "lp":
                flashButton("lp")
                playerPunch(side: .left)
            case "rp":
                flashButton("rp")
                playerPunch(side: .right)
            case "dodge":
                flashButton("dodge")
                playerDodge()
            case "star":
                flashButton("star")
                starPunch()
            case "lb":
                guard !playerExhausted else { continue }
                _ = registerPress()
                blockTouches[touch] = .left
                refreshBlockState()
            case "rb":
                guard !playerExhausted else { continue }
                _ = registerPress()
                blockTouches[touch] = .right
                refreshBlockState()
            default:
                break
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if blockTouches.removeValue(forKey: touch) != nil {
                refreshBlockState()
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if blockTouches.removeValue(forKey: touch) != nil {
                refreshBlockState()
            }
        }
    }

    private func refreshBlockState() {
        // Latest-held block wins; blocking pauses regen and drains stamina.
        playerBlockSide = blockTouches.values.reversed().first ?? blockTouches.values.first
        if playerExhausted {
            playerBlockSide = nil
        }
        buttons["lb"]?.fillColor = playerBlockSide == .left
            ? SKColor(red: 0.3, green: 0.45, blue: 0.85, alpha: 1)
            : SKColor(red: 0.13, green: 0.22, blue: 0.5, alpha: 0.95)
        buttons["rb"]?.fillColor = playerBlockSide == .right
            ? SKColor(red: 0.3, green: 0.45, blue: 0.85, alpha: 1)
            : SKColor(red: 0.13, green: 0.22, blue: 0.5, alpha: 0.95)
        refreshPlayerBasePose()
    }
}
