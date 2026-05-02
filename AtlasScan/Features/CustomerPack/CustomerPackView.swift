import SwiftUI
import AtlasContracts

// MARK: - CustomerPackView
//
// Decision-first customer recommendation pack display.
//
// Presents a CustomerPackV1 as a guided decision journey:
//   1. Hero / decision  — one clear system recommendation
//   2. Why this works   — physics translated to outcomes
//   3. What if you don't — anti-default argument (honest, not alarmist)
//   4. What changes     — tangible daily-life benefits
//   5. The full system  — every component explained
//   6. Daily use        — real-life household scenarios
//   7. Future path      — upgrade options this system enables
//   8. Close            — final statement + next step
//
// Rules:
//   • Confident tone — "This is the right fit", not "This may work well"
//   • No marketing claims — outcomes must derive from survey data
//   • No raw heat-loss numbers or physics jargon
//   • No greenwashing or fake efficiency claims

struct CustomerPackView: View {

    let pack: CustomerPackV1

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                heroSection
                decisionSection
                whySection
                antiDefaultSection
                benefitsSection
                fullSystemSection
                dailyUseSection
                futurePathSection
                closeSection
            }
        }
        .navigationTitle("Your Recommendation")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let name = pack.customerName {
                Text("Prepared for \(name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let address = pack.propertyAddress {
                Text(address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(pack.decision.systemName)
                .font(.title2.bold())
                .padding(.top, 4)
            Text(pack.decision.outcomeStatement)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Section 1: The decision

    private var decisionSection: some View {
        packSection(symbol: "checkmark.seal.fill", title: "The right system for your home", tint: .accentColor) {
            Text(pack.decision.rationale)
                .font(.body)
        }
    }

    // MARK: - Section 2: Why this works

    private var whySection: some View {
        packSection(symbol: "lightbulb.fill", title: "Why this works", tint: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                Text(pack.whyThisSystem.behaviourStatement)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                ForEach(pack.whyThisSystem.reasons, id: \.label) { reason in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(reason.label)
                            .font(.subheadline.bold())
                        Text(reason.explanation)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Section 3: What happens if you don't

    private var antiDefaultSection: some View {
        packSection(symbol: "exclamationmark.triangle.fill", title: "What happens if you don't", tint: .red) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(pack.antiDefault.alternativeLabel) would:")
                    .font(.subheadline.bold())
                ForEach(pack.antiDefault.consequences, id: \.self) { consequence in
                    Label(consequence, systemImage: "xmark.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Section 4: What changes for you

    private var benefitsSection: some View {
        packSection(symbol: "star.fill", title: "What changes for you", tint: .green) {
            VStack(alignment: .leading, spacing: 10) {
                Text(pack.customerBenefits.headline)
                    .font(.subheadline.bold())
                    .padding(.bottom, 2)
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(pack.customerBenefits.benefits, id: \.label) { benefit in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: benefit.symbolName)
                                .font(.body)
                                .foregroundStyle(.green)
                                .frame(width: 20)
                            Text(benefit.label)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 5: The full system

    private var fullSystemSection: some View {
        packSection(symbol: "wrench.and.screwdriver.fill", title: "The full system", tint: .blue) {
            VStack(alignment: .leading, spacing: 12) {
                Text(pack.fullSystem.headline)
                    .font(.subheadline.bold())
                Text(pack.fullSystem.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                Divider()
                ForEach(pack.fullSystem.components, id: \.description) { component in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(component.description)
                            .font(.subheadline.bold())
                        Text(component.purpose)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                if !pack.fullSystem.futureReadyElements.isEmpty {
                    Divider()
                    Text("Future-ready")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(pack.fullSystem.futureReadyElements, id: \.self) { element in
                        Label(element, systemImage: "arrow.up.forward.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Section 6: Daily use

    private var dailyUseSection: some View {
        packSection(symbol: "calendar.day.timeline.left", title: "Daily use", tint: .purple) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(pack.dailyUse.scenarios, id: \.label) { scenario in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scenario.label)
                            .font(.subheadline.bold())
                        Text(scenario.outcome)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Section 7: Future path

    private var futurePathSection: some View {
        packSection(symbol: "arrow.up.right.circle.fill", title: "Future path", tint: .teal) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.teal)
                    Text("Today — \(pack.futurePath.todayStatement)")
                        .font(.body)
                }
                ForEach(pack.futurePath.upgradeOptions, id: \.label) { option in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(option.label, systemImage: "plus.circle.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(.teal)
                        Text(option.enabledBy)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Section 8: Close

    private var closeSection: some View {
        VStack(spacing: 16) {
            Text(pack.close.closingStatement)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            VStack(spacing: 6) {
                Text("Next step")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(pack.close.nextStepLabel)
                    .font(.headline)
                Text(pack.close.nextStepDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            Text("Reference: \(pack.visitReference)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(.secondarySystemGroupedBackground))
        .padding(.top, 8)
        .padding(.bottom, 32)
    }

    // MARK: - Shared section card layout

    @ViewBuilder
    private func packSection<Content: View>(
        symbol: String,
        title: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        CustomerPackView(pack: .preview)
    }
}

extension CustomerPackV1 {
    static let preview = CustomerPackV1(
        visitId: "preview-001",
        visitReference: "JOB-2025-0042",
        propertyAddress: "14 Meadow Lane, Bristol",
        customerName: "Mr & Mrs Thompson",
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        decision: CustomerPackDecisionV1(
            systemName: "Unvented cylinder system with high-efficiency boiler",
            outcomeStatement: "This is the right system for your home.",
            rationale: "Your property's demand profile and existing pipework layout make an unvented cylinder the correct fit — giving you reliable pressure and capacity without compromise."
        ),
        whyThisSystem: CustomerPackWhyV1(
            behaviourStatement: "Your home needs steady, reliable heat — not bursts.",
            reasons: [
                CustomerPackReasonV1(
                    label: "Consistent heat delivery",
                    explanation: "Your layout means heat needs to reach multiple zones reliably — this system does that without working hard."
                ),
                CustomerPackReasonV1(
                    label: "Hot water on demand",
                    explanation: "An unvented cylinder maintains mains pressure to every outlet, so demand across the household is met without waiting."
                ),
                CustomerPackReasonV1(
                    label: "Right-sized for your space",
                    explanation: "The system is matched to your actual heat load — not oversized, not undersized."
                ),
            ]
        ),
        antiDefault: CustomerPackAntiDefaultV1(
            alternativeLabel: "A simple like-for-like boiler swap",
            consequences: [
                "Cost more to run — the existing layout isn't efficient for your usage pattern",
                "Struggle at peak demand — hot water pressure will still drop under load",
                "Limit future upgrades — a heat pump or solar thermal cannot integrate cleanly",
            ]
        ),
        customerBenefits: CustomerPackBenefitsV1(
            headline: "Here's what improves in your daily life.",
            benefits: [
                CustomerPackBenefitV1(symbolName: "drop.fill",                    label: "Showers don't run out"),
                CustomerPackBenefitV1(symbolName: "thermometer.sun.fill",         label: "House warms evenly"),
                CustomerPackBenefitV1(symbolName: "chart.line.downtrend.xyaxis",  label: "Bills stabilise"),
                CustomerPackBenefitV1(symbolName: "clock.badge.checkmark.fill",   label: "System lasts longer"),
                CustomerPackBenefitV1(symbolName: "bolt.fill",                    label: "No cold-water shock"),
                CustomerPackBenefitV1(symbolName: "wrench.fill",                  label: "Fewer breakdowns"),
            ]
        ),
        fullSystem: CustomerPackFullSystemV1(
            headline: "This isn't just a boiler replacement.",
            summary: "It's how heat moves through your home, how hot water is delivered, and how the system adapts to your usage.",
            components: [
                CustomerPackComponentV1(
                    category: "boiler",
                    description: "High-efficiency condensing boiler",
                    purpose: "Provides reliable heat and hot water generation, sized for your property."
                ),
                CustomerPackComponentV1(
                    category: "cylinder",
                    description: "Mixergy smart unvented cylinder",
                    purpose: "Stores and delivers hot water at mains pressure, with intelligent heating to minimise energy use."
                ),
                CustomerPackComponentV1(
                    category: "controls",
                    description: "Smart zone controls",
                    purpose: "Lets you heat only the spaces you're using, when you're using them."
                ),
                CustomerPackComponentV1(
                    category: "pipework",
                    description: "Optimised pipework run",
                    purpose: "Reduces flow resistance so the system reaches temperature faster and holds it longer."
                ),
            ],
            futureReadyElements: [
                "Pre-plumbed for heat pump integration",
                "Solar thermal connection point included",
            ]
        ),
        dailyUse: CustomerPackDailyUseV1(
            scenarios: [
                CustomerPackScenarioV1(
                    label: "Morning rush",
                    outcome: "Hot water for everyone — no waiting, no cold drop."
                ),
                CustomerPackScenarioV1(
                    label: "Cold evening",
                    outcome: "The house reaches temperature quickly and holds it without cycling."
                ),
                CustomerPackScenarioV1(
                    label: "Extended away",
                    outcome: "Smart controls drop to setback automatically — no wasted heat."
                ),
            ]
        ),
        futurePath: CustomerPackFuturePathV1(
            todayStatement: "System works at full performance from day one.",
            upgradeOptions: [
                CustomerPackUpgradeOptionV1(
                    label: "Heat pump",
                    enabledBy: "The cylinder and pipework are sized and pre-plumbed to accept a heat pump without structural changes."
                ),
                CustomerPackUpgradeOptionV1(
                    label: "Solar thermal",
                    enabledBy: "A secondary coil is included in the cylinder, ready for solar connection."
                ),
                CustomerPackUpgradeOptionV1(
                    label: "Battery storage",
                    enabledBy: "Smart controls can integrate with a home battery to shift heating loads off peak tariffs."
                ),
            ]
        ),
        close: CustomerPackCloseV1(
            closingStatement: "This is the best outcome for your home.",
            nextStepLabel: "Installation planning",
            nextStepDescription: "Your engineer will contact you to arrange a convenient installation date and confirm the final specification."
        )
    )
}
#endif
