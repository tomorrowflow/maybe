import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["pensionFields", "cashoutFields", "surrenderValueField", "retirementDate"]

  static values = {
    pensionSubtypes: { type: Array, default: ["riester", "ruerup", "betriebsrente", "gesetzliche_rente", "versorgungswerk", "private_rentenversicherung"] },
    cashableSubtypes: { type: Array, default: ["private_rentenversicherung"] },
    personRetirementDates: { type: Object, default: {} }
  }

  togglePensionFields(event) {
    const selectedSubtype = event.target.value
    const isPensionType = this.pensionSubtypesValue.includes(selectedSubtype)
    const isCashableType = this.cashableSubtypesValue.includes(selectedSubtype)

    if (this.hasPensionFieldsTarget) {
      if (isPensionType) {
        this.pensionFieldsTarget.classList.remove("hidden")
      } else {
        this.pensionFieldsTarget.classList.add("hidden")
      }
    }

    if (this.hasCashoutFieldsTarget) {
      if (isCashableType) {
        this.cashoutFieldsTarget.classList.remove("hidden")
      } else {
        this.cashoutFieldsTarget.classList.add("hidden")
      }
    }
  }

  toggleSurrenderValue(event) {
    if (this.hasSurrenderValueFieldTarget) {
      if (event.target.checked) {
        this.surrenderValueFieldTarget.classList.remove("hidden")
      } else {
        this.surrenderValueFieldTarget.classList.add("hidden")
      }
    }
  }

  connect() {
    // Listen for ownership selector changes (the selector is outside this controller's scope)
    this._ownershipSelect = this.element.closest("form")?.querySelector("[name='account[ownership_selection]']")
    if (this._ownershipSelect) {
      this._boundPrefill = this._prefillRetirementDate.bind(this)
      this._ownershipSelect.addEventListener("change", this._boundPrefill)
    }
  }

  disconnect() {
    if (this._ownershipSelect && this._boundPrefill) {
      this._ownershipSelect.removeEventListener("change", this._boundPrefill)
    }
  }

  // Pre-fill retirement date from the selected person's estimated retirement date
  _prefillRetirementDate(event) {
    if (!this.hasRetirementDateTarget) return

    const selection = event.target.value
    if (!selection || !selection.startsWith("personal_")) return

    // Only pre-fill if the field is currently empty
    if (this.retirementDateTarget.value) return

    const personId = selection.replace("personal_", "")
    const retirementDate = this.personRetirementDatesValue[personId]
    if (retirementDate) {
      this.retirementDateTarget.value = retirementDate
    }
  }
}
