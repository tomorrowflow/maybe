import { Controller } from "@hotwired/stimulus"

// Automatically removes its element after a configurable delay.
// Usage: data-controller="auto-dismiss" data-auto-dismiss-delay-value="5000"
export default class extends Controller {
  static values = { delay: { type: Number, default: 5000 } }

  connect() {
    this.timeout = setTimeout(() => {
      this.element.remove()
    }, this.delayValue)
  }

  disconnect() {
    if (this.timeout) clearTimeout(this.timeout)
  }
}
