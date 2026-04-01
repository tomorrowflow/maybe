import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["expenseInput", "contributionInput", "targetAgeInput", "growthRateInput",
                     "applyButton", "loadingIndicator", "results", "exploredRate"]
  static values = {
    url: String,
    applyUrl: String,
    debounce: { type: Number, default: 600 }
  }

  connect() {
    this._timeout = null
    this._abortController = null
    this._initialValues = this._captureCurrentValues()
  }

  disconnect() {
    clearTimeout(this._timeout)
    this._abortController?.abort()
  }

  paramChanged() {
    this._scheduleExplore()
  }

  apply() {
    // Submit as form to apply_exploration endpoint
    const form = document.createElement("form")
    form.method = "POST"
    form.action = this.applyUrlValue

    // CSRF token
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    if (csrfToken) {
      const tokenInput = document.createElement("input")
      tokenInput.type = "hidden"
      tokenInput.name = "authenticity_token"
      tokenInput.value = csrfToken
      form.appendChild(tokenInput)
    }

    // Method override for PATCH
    const methodInput = document.createElement("input")
    methodInput.type = "hidden"
    methodInput.name = "_method"
    methodInput.value = "patch"
    form.appendChild(methodInput)

    // Add current values
    const params = this._collectParams()
    for (const [key, value] of Object.entries(params)) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = key
      input.value = value
      form.appendChild(input)
    }

    document.body.appendChild(form)
    form.submit()
  }

  // Private

  _scheduleExplore() {
    clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this._explore(), this.debounceValue)
    this._toggleApplyButton()
  }

  async _explore() {
    this._abortController?.abort()
    this._abortController = new AbortController()

    this._showLoading()
    this._showResults()

    const params = new URLSearchParams(this._collectParams())

    try {
      const response = await fetch(`${this.urlValue}?${params.toString()}`, {
        headers: {
          "Accept": "text/vnd.turbo-stream.html",
          "X-Requested-With": "XMLHttpRequest"
        },
        signal: this._abortController.signal
      })

      if (response.ok) {
        const html = await response.text()
        Turbo.renderStreamMessage(html)
      }
    } catch (error) {
      if (error.name !== "AbortError") {
        console.error("Exploration failed:", error)
      }
    } finally {
      this._hideLoading()
    }
  }

  _collectParams() {
    const params = {}
    if (this.hasExpenseInputTarget) params.retirement_monthly_expenses = this.expenseInputTarget.value
    if (this.hasContributionInputTarget) params.monthly_contribution = this.contributionInputTarget.value
    if (this.hasTargetAgeInputTarget) params.target_age = this.targetAgeInputTarget.value
    if (this.hasGrowthRateInputTarget) params.portfolio_growth_rate = this.growthRateInputTarget.value
    return params
  }

  _captureCurrentValues() {
    return JSON.stringify(this._collectParams())
  }

  _toggleApplyButton() {
    if (!this.hasApplyButtonTarget) return
    const changed = JSON.stringify(this._collectParams()) !== this._initialValues
    this.applyButtonTarget.classList.toggle("hidden", !changed)
  }

  _showResults() {
    if (this.hasResultsTarget) this.resultsTarget.classList.remove("hidden")
  }

  _showLoading() {
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.classList.remove("hidden")
  }

  _hideLoading() {
    if (this.hasLoadingIndicatorTarget) this.loadingIndicatorTarget.classList.add("hidden")
  }
}
