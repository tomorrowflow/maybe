import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["select", "personSelect", "checkbox"]

  toggle() {
    const value = this.selectTarget.value

    if (value === "household") {
      this.personSelectTarget.classList.add("hidden")
      this.uncheckAll()
    } else {
      this.personSelectTarget.classList.remove("hidden")
    }
  }

  uncheckAll() {
    this.checkboxTargets.forEach(cb => cb.checked = false)
  }
}
