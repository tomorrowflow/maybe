import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "nav", "backButton"]
  static values = {
    currentStep: { type: String, default: "basics" },
    exitPath: { type: String, default: "/" }
  }

  connect() {
    this.steps = ["basics", "income", "portfolio"]
    this.showStep(this.currentStepValue)

    // Listen for global events (nav elements are outside controller scope)
    this.handleGlobalBack = this.goBack.bind(this)
    this.handleGlobalGoToStep = this.goToStepFromEvent.bind(this)

    document.addEventListener("retirement-wizard:back", this.handleGlobalBack)
    document.addEventListener("retirement-wizard:go-to-step", this.handleGlobalGoToStep)

    // Re-enable all inputs before form submission so hidden fields are included
    this.element.querySelector("form")?.addEventListener("submit", this.enableAllInputs.bind(this))
  }

  disconnect() {
    document.removeEventListener("retirement-wizard:back", this.handleGlobalBack)
    document.removeEventListener("retirement-wizard:go-to-step", this.handleGlobalGoToStep)
  }

  // Handle go-to-step from custom event (breadcrumb clicks)
  goToStepFromEvent(event) {
    const { step, stepIndex } = event.detail
    const currentIndex = this.steps.indexOf(this.currentStepValue)

    // Only allow going to completed steps or current step
    if (stepIndex <= currentIndex && this.steps.includes(step)) {
      this.currentStepValue = step
      this.showStep(step)
    }
  }

  nextStep(event) {
    const nextStep = event.currentTarget.dataset.wizardNextStep
    if (nextStep && this.steps.includes(nextStep)) {
      this.currentStepValue = nextStep
      this.showStep(nextStep)
    }
  }

  prevStep(event) {
    const prevStep = event.currentTarget.dataset.wizardPrevStep
    if (prevStep && this.steps.includes(prevStep)) {
      this.currentStepValue = prevStep
      this.showStep(prevStep)
    }
  }

  // Go back to previous step, or exit if on first step
  goBack(event) {
    if (event && event.preventDefault) {
      event.preventDefault()
    }

    const currentIndex = this.steps.indexOf(this.currentStepValue)

    if (currentIndex > 0) {
      // Go to previous step
      const prevStep = this.steps[currentIndex - 1]
      this.currentStepValue = prevStep
      this.showStep(prevStep)
    } else {
      // On first step, navigate to exit path
      window.location.href = this.exitPathValue
    }
  }

  goToStep(event) {
    const step = event.currentTarget.dataset.step
    const stepIndex = parseInt(event.currentTarget.dataset.stepIndex, 10)
    const currentIndex = this.steps.indexOf(this.currentStepValue)

    // Only allow going to completed steps or current step
    if (stepIndex <= currentIndex && this.steps.includes(step)) {
      this.currentStepValue = step
      this.showStep(step)
    }
  }

  showStep(stepName) {
    // Show/hide step content and manage input states for validation
    this.stepTargets.forEach(step => {
      const isCurrentStep = step.dataset.step === stepName
      if (isCurrentStep) {
        step.classList.remove("hidden")
        // Enable inputs in visible step
        this.setInputsDisabled(step, false)
      } else {
        step.classList.add("hidden")
        // Disable inputs in hidden steps to bypass browser validation
        this.setInputsDisabled(step, true)
      }
    })

    // Update navigation indicators
    // Note: Nav elements are in the header (outside controller scope), so we query globally
    const currentIndex = this.steps.indexOf(stepName)
    const navElements = document.querySelectorAll("[data-retirement-wizard-nav]")

    navElements.forEach((nav) => {
      const navStepKey = nav.dataset.stepKey
      const navIndex = this.steps.indexOf(navStepKey)
      const isComplete = navIndex < currentIndex
      const isCurrent = navStepKey === stepName

      const container = nav.querySelector("[data-step-container]")
      const indicator = nav.querySelector("[data-step-indicator]")

      if (container) {
        container.classList.remove("text-primary", "text-secondary", "text-green-600")
        if (isCurrent) {
          container.classList.add("text-primary")
        } else if (isComplete) {
          container.classList.add("text-green-600")
        } else {
          container.classList.add("text-secondary")
        }
      }

      if (indicator) {
        indicator.classList.remove(
          "bg-primary", "bg-green-600/10", "bg-container-inset",
          "border-alpha-black-25", "text-primary"
        )

        if (isCurrent) {
          indicator.classList.add("bg-primary", "text-primary")
          indicator.innerHTML = navIndex + 1
        } else if (isComplete) {
          indicator.classList.add("bg-green-600/10", "border-alpha-black-25")
          indicator.innerHTML = `<svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 6L9 17l-5-5"/></svg>`
        } else {
          indicator.classList.add("bg-container-inset")
          indicator.innerHTML = navIndex + 1
        }
      }
    })

    // Scroll to top
    window.scrollTo({ top: 0, behavior: "smooth" })
  }

  // Helper to disable/enable all form inputs in a step container
  setInputsDisabled(container, disabled) {
    const inputs = container.querySelectorAll("input, select, textarea")
    inputs.forEach(input => {
      if (disabled) {
        // Store original disabled state and disable
        if (!input.hasAttribute("data-originally-disabled")) {
          input.setAttribute("data-originally-disabled", input.disabled)
        }
        input.disabled = true
      } else {
        // Restore original disabled state
        const wasOriginallyDisabled = input.getAttribute("data-originally-disabled") === "true"
        input.disabled = wasOriginallyDisabled
        input.removeAttribute("data-originally-disabled")
      }
    })
  }

  // Re-enable all inputs before form submission
  enableAllInputs(event) {
    this.stepTargets.forEach(step => {
      this.setInputsDisabled(step, false)
    })
  }
}
