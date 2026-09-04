import SwiftUI

struct OnboardingView: View {
    @StateObject private var viewModel: OnboardingViewModel
    @AccessibilityFocusState private var focusedPage: OnboardingPage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(onboardingState: OnboardingState) {
        _viewModel = StateObject(
            wrappedValue: OnboardingViewModel(onboardingState: onboardingState)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.large) {
                    progress
                    pageContent
                }
                .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
                .padding(AppSpacing.page)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            controls
        }
        .onAppear {
            focusedPage = viewModel.currentPage
        }
        .onChange(of: viewModel.currentPage) { _, newPage in
            focusedPage = newPage
        }
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Text("Step \(viewModel.currentStep) of \(viewModel.totalSteps)")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("onboarding-progress")

            ProgressView(
                value: Double(viewModel.currentStep),
                total: Double(viewModel.totalSteps)
            )
            .accessibilityHidden(true)
        }
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: AppSpacing.medium) {
            Image(systemName: viewModel.currentPage.symbolName)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(viewModel.currentPage.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($focusedPage, equals: viewModel.currentPage)
                .accessibilityIdentifier("onboarding-heading")

            Text(viewModel.currentPage.summary)
                .font(.body)

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                ForEach(viewModel.currentPage.details, id: \.self) { detail in
                    Text(detail)
                        .font(.body)
                }
            }
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.medium) {
                if viewModel.canGoBack {
                    backButton
                }
                primaryButton
            }

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                if viewModel.canGoBack {
                    backButton
                }
                primaryButton
            }
        }
        .frame(maxWidth: AppLayout.maximumReadableWidth, alignment: .leading)
        .padding(.horizontal, AppSpacing.page)
        .padding(.vertical, AppSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var backButton: some View {
        Button("Back") {
            changePage { viewModel.goBack() }
        }
        .buttonStyle(.bordered)
        .frame(minHeight: AppLayout.minimumTouchTarget)
        .accessibilityIdentifier("onboarding-back")
    }

    private var primaryButton: some View {
        Button(viewModel.primaryActionTitle) {
            changePage { viewModel.continueOrComplete() }
        }
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: .infinity, minHeight: AppLayout.minimumTouchTarget)
        .accessibilityIdentifier("onboarding-continue")
    }

    private func changePage(_ action: () -> Void) {
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeInOut(duration: 0.2), action)
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(
            onboardingState: OnboardingState(
                store: InMemoryOnboardingCompletionStore()
            )
        )
    }
}
