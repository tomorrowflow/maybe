import { Controller } from "@hotwired/stimulus"
import * as d3 from "d3"

// Monte Carlo confidence band chart using D3.js
// Renders a fan chart with p10-p90 bands and p50 median line
export default class extends Controller {
  static values = {
    data: Object
  }

  connect() {
    if (this.hasDataValue && this.dataValue.percentiles) {
      this._renderChart()
    }
  }

  dataValueChanged() {
    if (this.dataValue.percentiles) {
      this._renderChart()
    }
  }

  _renderChart() {
    this.element.innerHTML = ""

    const data = this.dataValue
    const percentiles = data.percentiles
    const years = data.years || []

    if (!percentiles || !years.length) {
      this.element.innerHTML = '<p class="text-sm text-subdued text-center">No simulation data available</p>'
      return
    }

    const container = this.element
    const width = container.clientWidth
    const height = container.clientHeight || 256
    const margin = { top: 20, right: 20, bottom: 30, left: 60 }
    const innerWidth = width - margin.left - margin.right
    const innerHeight = height - margin.top - margin.bottom

    const svg = d3.select(container)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`)

    // Scales
    const xScale = d3.scaleLinear()
      .domain([0, years[years.length - 1]])
      .range([0, innerWidth])

    const allValues = [
      ...percentiles.p10,
      ...percentiles.p90
    ].filter(v => v != null)

    const yScale = d3.scaleLinear()
      .domain([0, d3.max(allValues) * 1.1])
      .range([innerHeight, 0])

    // Axes
    svg.append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(d3.axisBottom(xScale).ticks(Math.min(years.length, 10)).tickFormat(d => `Year ${d}`))
      .selectAll("text")
      .attr("class", "text-xs fill-secondary")

    svg.append("g")
      .call(d3.axisLeft(yScale).ticks(5).tickFormat(d => {
        if (d >= 1000000) return `${(d / 1000000).toFixed(1)}M`
        if (d >= 1000) return `${(d / 1000).toFixed(0)}K`
        return d
      }))
      .selectAll("text")
      .attr("class", "text-xs fill-secondary")

    // Light band (p10-p90)
    const area1090 = d3.area()
      .x((d, i) => xScale(years[i]))
      .y0((d, i) => yScale(percentiles.p10[i] || 0))
      .y1((d, i) => yScale(percentiles.p90[i] || 0))

    svg.append("path")
      .datum(years)
      .attr("d", area1090)
      .attr("fill", "rgba(59, 130, 246, 0.1)")

    // Dark band (p25-p75)
    const area2575 = d3.area()
      .x((d, i) => xScale(years[i]))
      .y0((d, i) => yScale(percentiles.p25[i] || 0))
      .y1((d, i) => yScale(percentiles.p75[i] || 0))

    svg.append("path")
      .datum(years)
      .attr("d", area2575)
      .attr("fill", "rgba(59, 130, 246, 0.2)")

    // Median line (p50)
    const line = d3.line()
      .x((d, i) => xScale(years[i]))
      .y((d, i) => yScale(percentiles.p50[i] || 0))

    svg.append("path")
      .datum(years)
      .attr("d", line)
      .attr("fill", "none")
      .attr("stroke", "rgb(59, 130, 246)")
      .attr("stroke-width", 2)

    // Zero line
    svg.append("line")
      .attr("x1", 0)
      .attr("x2", innerWidth)
      .attr("y1", yScale(0))
      .attr("y2", yScale(0))
      .attr("stroke", "rgba(239, 68, 68, 0.3)")
      .attr("stroke-dasharray", "4,4")
  }
}
