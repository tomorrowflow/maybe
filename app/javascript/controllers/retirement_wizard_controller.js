import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["step", "nav"]
  static values = { currentStep: { type: String, default: "basics" } }

  connect() {
    this.steps = ["basics", "income", "portfolio"]
    this.showStep(this.currentStepValue)
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
    // Show/hide step content
    this.stepTargets.forEach(step => {
      if (step.dataset.step === stepName) {
        step.classList.remove("hidden")
      } else {
        step.classList.add("hidden")
      }
    })

    // Update navigation indicators
    const currentIndex = this.steps.indexOf(stepName)

    this.navTargets.forEach((nav) => {
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
}
