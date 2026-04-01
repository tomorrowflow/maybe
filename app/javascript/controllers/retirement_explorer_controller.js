import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slider", "dateLabel", "payoutDate", "applyButton", "loadingIndicator"]
  static values = {
    url: String,
    applyUrl: String,
    debounce: { type: Number, default: 400 }
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

  // Called on slider `input` event — updates label immediately, debounces server call
  sliderChanged(event) {
    const slider = event.currentTarget
    const dateStr = this._sliderValueToDate(slider)

    // Update the adjacent date label
    const labelId = slider.dataset.labelTarget
    const label = document.getElementById(labelId)
    if (label) label.textContent = this._formatDate(dateStr)

    this._scheduleExplore()
  }

  // Called on payout date `change` event
  payoutDateChanged() {
    this._scheduleExplore()
  }

  // Apply explored dates to the scenario
  apply() {
    const form = document.getElementById("apply-exploration-form")
    if (!form) return

    // Clear existing dynamic hidden fields
    form.querySelectorAll("input.explore-param").forEach(el => el.remove())

    // Add current slider values
    this.sliderTargets.forEach(slider => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = slider.dataset.paramName
      input.value = this._sliderValueToDate(slider)
      input.classList.add("explore-param")
      form.appendChild(input)
    })

    // Add current payout date values
    this.payoutDateTargets.forEach(dateInput => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = dateInput.dataset.paramName
      input.value = dateInput.value
      input.classList.add("explore-param")
      form.appendChild(input)
    })

    form.requestSubmit()
  }

  // Private

  _scheduleExplore() {
    clearTimeout(this._timeout)
    this._timeout = setTimeout(() => this._explore(), this.debounceValue)
    this._toggleApplyButton()
  }

  async _explore() {
    // Abort any in-flight request
    this._abortController?.abort()
    this._abortController = new AbortController()

    this._showLoading()

    const params = new URLSearchParams()

    // Collect slider values
    this.sliderTargets.forEach(slider => {
      const paramName = slider.dataset.paramName
      const dateStr = this._sliderValueToDate(slider)
      params.append(paramName, dateStr)
    })

    // Collect payout date values
    this.payoutDateTargets.forEach(input => {
      const paramName = input.dataset.paramName
      if (input.value) params.append(paramName, input.value)
    })

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

  _sliderValueToDate(slider) {
    const epochDate = new Date(slider.dataset.epochDate + "T00:00:00")
    const days = parseInt(slider.value, 10)
    const date = new Date(epochDate.getTime() + days * 86400000)
    return date.toISOString().split("T")[0]
  }

  _formatDate(isoDate) {
    const d = new Date(isoDate + "T00:00:00")
    return d.toLocaleDateString(undefined, { year: "numeric", month: "long" })
  }

  _captureCurrentValues() {
    const values = {}
    this.sliderTargets.forEach(s => { values[s.id] = s.value })
    this.payoutDateTargets.forEach(p => { values[p.id] = p.value })
    return values
  }

  _toggleApplyButton() {
    if (!this.hasApplyButtonTarget) return

    const current = this._captureCurrentValues()
    const changed = JSON.stringify(current) !== JSON.stringify(this._initialValues)
    this.applyButtonTarget.classList.toggle("hidden", !changed)
  }

  _showLoading() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove("hidden")
    }
  }

  _hideLoading() {
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add("hidden")
    }
  }
}
