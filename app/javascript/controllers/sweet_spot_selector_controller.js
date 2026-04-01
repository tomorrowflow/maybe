import { Controller } from "@hotwired/stimulus"

// Sliding window sweet spot selector
// Shows 5 tiles at a time, fetches additional years on demand
export default class extends Controller {
  static targets = ["tilesContainer", "detail", "prevButton", "nextButton", "loadingIndicator"]
  static values = {
    strategies: { type: Array, default: [] },
    visibleStart: { type: Number, default: 0 },
    activeIndex: { type: Number, default: 0 },
    personId: String,
    calculateUrl: String,
    earliestYear: Number,
    latestYear: Number,
    currency: { type: String, default: "EUR" }
  }

  static VISIBLE_COUNT = 5

  connect() {
    this._render()
  }

  select(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10)
    this.activeIndexValue = index
    this._render()
  }

  prev() {
    if (this.activeIndexValue > 0) {
      this.activeIndexValue--
      // Shift window if active goes before visible start
      if (this.activeIndexValue < this.visibleStartValue) {
        this.visibleStartValue = this.activeIndexValue
        this._ensureDataForVisibleRange()
      }
      this._render()
    }
  }

  next() {
    if (this.activeIndexValue < this.strategiesValue.length - 1) {
      this.activeIndexValue++
      // Shift window if active goes past visible end
      const visibleEnd = this.visibleStartValue + 5
      if (this.activeIndexValue >= visibleEnd) {
        this.visibleStartValue = this.activeIndexValue - 4
        this._ensureDataForVisibleRange()
      }
      this._render()
    }
  }

  _render() {
    const strategies = this.strategiesValue
    const active = this.activeIndexValue
    const visStart = this.visibleStartValue
    const visEnd = Math.min(visStart + 5, strategies.length)

    // Render tiles
    if (this.hasTilesContainerTarget) {
      let html = ""
      for (let i = visStart; i < visEnd; i++) {
        const s = strategies[i]
        if (!s) continue
        const isActive = i === active
        const year = s.date ? new Date(s.date).getFullYear() : "?"

        const feasible = s.feasible
        const barColor = feasible ? (s.success_rate >= 85 ? "bg-green-500" : "bg-yellow-500") : "bg-red-400"

        // Bar height from savings_after_gap
        const savings = strategies.map(st => st.savings_after_gap || 0)
        const minS = Math.min(...savings)
        const maxS = Math.max(...savings)
        const range = maxS - minS
        const barPct = range > 0 ? 20 + ((s.savings_after_gap - minS) / range) * 80 : 50

        const ringClass = isActive ? "ring-2 ring-blue-500 scale-110 z-10" : ""

        html += `
          <button class="flex flex-col items-center gap-1 cursor-pointer transition-transform min-w-[56px] ${ringClass}"
                  data-index="${i}" data-action="click->sweet-spot-selector#select">
            <div class="w-full rounded-t-md ${barColor} transition-all" style="height: ${barPct}px"></div>
            <span class="text-[10px] font-medium text-secondary">${year}</span>
          </button>
        `
      }
      this.tilesContainerTarget.innerHTML = html
    }

    // Render detail for active strategy
    this.detailTargets.forEach((el, i) => {
      el.classList.toggle("hidden", i !== active)
    })

    // Update arrows
    if (this.hasPrevButtonTarget) {
      const atStart = active <= 0
      this.prevButtonTarget.classList.toggle("opacity-30", atStart)
      this.prevButtonTarget.classList.toggle("pointer-events-none", atStart)
    }
    if (this.hasNextButtonTarget) {
      const atEnd = active >= strategies.length - 1
      this.nextButtonTarget.classList.toggle("opacity-30", atEnd)
      this.nextButtonTarget.classList.toggle("pointer-events-none", atEnd)
    }
  }

  async _ensureDataForVisibleRange() {
    // Check if we need to fetch any years that aren't yet calculated
    // For now, all years are pre-calculated by the background job
    // This is a placeholder for future on-demand fetching
  }
}
