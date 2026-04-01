import { Controller } from "@hotwired/stimulus"

// Persists form field values to localStorage so they survive modal dismissals.
// On connect, restores any saved values. On input/change, saves current values.
// Clears storage on successful form submission.
//
// Usage:
//   <form data-controller="form-persist" data-form-persist-key-value="new-investment">
//
export default class extends Controller {
  static values = {
    key: String  // unique storage key per form type
  }

  connect() {
    this._restore()

    this._boundSave = this._save.bind(this)
    this._boundClear = this._clear.bind(this)

    this.element.addEventListener("input", this._boundSave)
    this.element.addEventListener("change", this._boundSave)
    this.element.addEventListener("submit", this._boundClear)
  }

  disconnect() {
    this.element.removeEventListener("input", this._boundSave)
    this.element.removeEventListener("change", this._boundSave)
    this.element.removeEventListener("submit", this._boundClear)
  }

  _storageKey() {
    return `form-persist:${this.keyValue}`
  }

  _save() {
    const data = {}
    const fields = this.element.querySelectorAll("input, select, textarea")

    fields.forEach(field => {
      // Skip CSRF tokens, hidden method fields, and fields without names
      if (!field.name || field.name === "authenticity_token" || field.name === "_method") return
      // Skip file inputs
      if (field.type === "file") return
      // Skip hidden fields that aren't user-editable (but keep hidden fields for things like return_to)
      if (field.type === "hidden" && !field.dataset.persist) return

      if (field.type === "checkbox") {
        data[field.name] = field.checked
      } else if (field.type === "radio") {
        if (field.checked) data[field.name] = field.value
      } else {
        data[field.name] = field.value
      }
    })

    try {
      localStorage.setItem(this._storageKey(), JSON.stringify(data))
    } catch (e) {
      // localStorage full or unavailable — silently ignore
    }
  }

  _restore() {
    let data
    try {
      const stored = localStorage.getItem(this._storageKey())
      if (!stored) return
      data = JSON.parse(stored)
    } catch (e) {
      return
    }

    const fields = this.element.querySelectorAll("input, select, textarea")

    fields.forEach(field => {
      if (!field.name || !(field.name in data)) return
      // Don't override server-provided values on edit forms (fields with existing values)
      if (field.dataset.persistSkipRestore) return

      const value = data[field.name]

      if (field.type === "checkbox") {
        field.checked = value
      } else if (field.type === "radio") {
        field.checked = (field.value === value)
      } else if (field.value === "" || field.value === field.defaultValue) {
        // Only restore if the field is empty or at its default
        field.value = value

        // Trigger change event so other Stimulus controllers react (e.g., investment-form showing pension fields)
        field.dispatchEvent(new Event("change", { bubbles: true }))
      }
    })
  }

  _clear() {
    try {
      localStorage.removeItem(this._storageKey())
    } catch (e) {
      // silently ignore
    }
  }
}
