import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pensionFields"]

  static values = {
    pensionSubtypes: { type: Array, default: ["riester", "ruerup", "betriebsrente"] }
  }

  togglePensionFields(event) {
    const selectedSubtype = event.target.value
    const isPensionType = this.pensionSubtypesValue.includes(selectedSubtype)

    if (this.hasPensionFieldsTarget) {
      if (isPensionType) {
        this.pensionFieldsTarget.classList.remove("hidden")
      } else {
        this.pensionFieldsTarget.classList.add("hidden")
      }
    }
  }
}
