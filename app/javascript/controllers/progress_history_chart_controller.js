import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";

const parseLocalDate = d3.timeParse("%Y-%m-%d");

export default class extends Controller {
  static values = {
    data: Object,
  };

  _d3SvgMemo = null;
  _d3GroupMemo = null;
  _d3Tooltip = null;
  _d3InitialContainerWidth = 0;
  _d3InitialContainerHeight = 0;
  _resizeObserver = null;

  // Color scheme
  _colors = {
    actual: "#3B82F6", // blue
    projected: "#9CA3AF", // gray
    required: "#22C55E", // green
    variance_positive: "#10B981", // emerald (ahead)
    variance_negative: "#EF4444", // red (behind)
  };

  connect() {
    this._install();
    document.addEventListener("turbo:load", this._reinstall);
    this._setupResizeObserver();
  }

  disconnect() {
    this._teardown();
    document.removeEventListener("turbo:load", this._reinstall);
    this._resizeObserver?.disconnect();
  }

  _reinstall = () => {
    this._teardown();
    this._install();
  };

  _teardown() {
    this._d3SvgMemo = null;
    this._d3GroupMemo = null;
    this._d3Tooltip = null;
    this._d3Container.selectAll("*").remove();
  }

  _install() {
    this._rememberInitialContainerSize();
    this._draw();
  }

  _rememberInitialContainerSize() {
    this._d3InitialContainerWidth = this._d3Container.node().clientWidth;
    this._d3InitialContainerHeight = this._d3Container.node().clientHeight;
  }

  _draw() {
    const metadata = this.dataValue.metadata;
    if (!metadata || !metadata.has_data) {
      this._drawEmpty();
      return;
    }

    this._drawChart();
  }

  _drawEmpty() {
    this._d3Svg
      .append("text")
      .attr("x", this._d3InitialContainerWidth / 2)
      .attr("y", this._d3InitialContainerHeight / 2)
      .attr("text-anchor", "middle")
      .attr("class", "text-secondary")
      .style("font-size", "14px")
      .text("No snapshot history yet");
  }

  _drawChart() {
    this._drawGridLines();
    this._drawRequiredLine();
    this._drawProjectedLine();
    this._drawActualLine();
    this._drawCurrentPoint();
    this._drawDataPoints();
    this._drawAxes();
    this._drawLegend();
    this._drawTooltip();
    this._trackMouseForShowingTooltip();
  }

  _drawGridLines() {
    const yTicks = this._d3YScale.ticks(5);

    this._d3Group
      .selectAll(".grid-line-h")
      .data(yTicks)
      .join("line")
      .attr("class", "grid-line-h")
      .attr("x1", 0)
      .attr("x2", this._d3ContainerWidth)
      .attr("y1", (d) => this._d3YScale(d))
      .attr("y2", (d) => this._d3YScale(d))
      .attr("stroke", "var(--color-gray-200)")
      .attr("stroke-dasharray", "2,2")
      .attr("opacity", 0.5);
  }

  _drawRequiredLine() {
    const requiredData = this.dataValue.series.required;
    if (!requiredData || requiredData.length === 0) return;

    const lineData = requiredData.map((d) => ({
      date: parseLocalDate(d.date),
      value: d.value,
    }));

    const line = d3
      .line()
      .x((d) => this._d3XScale(d.date))
      .y((d) => this._d3YScale(d.value))
      .curve(d3.curveMonotoneX);

    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("class", "required-line")
      .attr("fill", "none")
      .attr("stroke", this._colors.required)
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "6,4")
      .attr("opacity", 0.7);
  }

  _drawProjectedLine() {
    const projectedData = this.dataValue.series.projected;
    if (!projectedData || projectedData.length < 2) return;

    const lineData = projectedData.map((d) => ({
      date: parseLocalDate(d.date),
      value: d.value,
    }));

    const line = d3
      .line()
      .x((d) => this._d3XScale(d.date))
      .y((d) => this._d3YScale(d.value))
      .curve(d3.curveMonotoneX);

    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("class", "projected-line")
      .attr("fill", "none")
      .attr("stroke", this._colors.projected)
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "4,4")
      .attr("opacity", 0.6);
  }

  _drawActualLine() {
    const actualData = this.dataValue.series.actual;
    if (!actualData || actualData.length === 0) return;

    const lineData = actualData.map((d) => ({
      date: parseLocalDate(d.date),
      value: d.value,
    }));

    // Area under the line
    const area = d3
      .area()
      .x((d) => this._d3XScale(d.date))
      .y0(this._d3ContainerHeight)
      .y1((d) => this._d3YScale(d.value))
      .curve(d3.curveMonotoneX);

    // Gradient
    const gradient = this._d3Svg
      .append("defs")
      .append("linearGradient")
      .attr("id", `actual-gradient-${this.element.id}`)
      .attr("x1", "0%")
      .attr("y1", "0%")
      .attr("x2", "0%")
      .attr("y2", "100%");

    gradient
      .append("stop")
      .attr("offset", "0%")
      .attr("stop-color", this._colors.actual)
      .attr("stop-opacity", 0.2);

    gradient
      .append("stop")
      .attr("offset", "100%")
      .attr("stop-color", this._colors.actual)
      .attr("stop-opacity", 0.02);

    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("class", "actual-area")
      .attr("fill", `url(#actual-gradient-${this.element.id})`)
      .attr("d", area);

    // Line
    const line = d3
      .line()
      .x((d) => this._d3XScale(d.date))
      .y((d) => this._d3YScale(d.value))
      .curve(d3.curveMonotoneX);

    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("class", "actual-line")
      .attr("fill", "none")
      .attr("stroke", this._colors.actual)
      .attr("stroke-width", 2.5);

    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("d", line)
      .attr("fill", "none")
      .attr("stroke", this._colors.actual)
      .attr("stroke-width", 2.5);
  }

  _drawDataPoints() {
    const actualData = this.dataValue.series.actual;
    if (!actualData || actualData.length === 0) return;

    const pointData = actualData.map((d) => ({
      date: parseLocalDate(d.date),
      value: d.value,
      progress: d.progress_percent,
    }));

    this._d3Group
      .selectAll(".data-point")
      .data(pointData)
      .join("circle")
      .attr("class", "data-point")
      .attr("cx", (d) => this._d3XScale(d.date))
      .attr("cy", (d) => this._d3YScale(d.value))
      .attr("r", 4)
      .attr("fill", this._colors.actual)
      .attr("stroke", "#fff")
      .attr("stroke-width", 2);
  }

  _drawCurrentPoint() {
    const current = this.dataValue.current_point;
    if (!current) return;

    const date = parseLocalDate(current.date);
    const x = this._d3XScale(date);
    const y = this._d3YScale(current.actual_value);

    // Pulsing current point
    this._d3Group
      .append("circle")
      .attr("class", "current-point-pulse")
      .attr("cx", x)
      .attr("cy", y)
      .attr("r", 8)
      .attr("fill", this._colors.actual)
      .attr("opacity", 0.3);

    this._d3Group
      .append("circle")
      .attr("class", "current-point")
      .attr("cx", x)
      .attr("cy", y)
      .attr("r", 5)
      .attr("fill", this._colors.actual)
      .attr("stroke", "#fff")
      .attr("stroke-width", 2);

    // Label
    this._d3Group
      .append("text")
      .attr("x", x)
      .attr("y", y - 12)
      .attr("text-anchor", "middle")
      .attr("fill", this._colors.actual)
      .style("font-size", "10px")
      .style("font-weight", "600")
      .text("Today");
  }

  _drawAxes() {
    // X Axis
    const xAxisGroup = this._d3Group
      .append("g")
      .attr("transform", `translate(0,${this._d3ContainerHeight})`)
      .call(
        d3
          .axisBottom(this._d3XScale)
          .ticks(5)
          .tickFormat(d3.timeFormat("%b %Y"))
      );

    xAxisGroup.select(".domain").attr("stroke", "var(--color-gray-300)");
    xAxisGroup
      .selectAll(".tick line")
      .attr("stroke", "var(--color-gray-300)");
    xAxisGroup
      .selectAll(".tick text")
      .attr("fill", "var(--color-gray-500)")
      .style("font-size", "11px");

    // Y Axis
    const yAxisGroup = this._d3Group.append("g").call(
      d3
        .axisLeft(this._d3YScale)
        .ticks(5)
        .tickFormat((d) => this._formatCurrency(d))
    );

    yAxisGroup.select(".domain").attr("stroke", "var(--color-gray-300)");
    yAxisGroup
      .selectAll(".tick line")
      .attr("stroke", "var(--color-gray-300)");
    yAxisGroup
      .selectAll(".tick text")
      .attr("fill", "var(--color-gray-500)")
      .style("font-size", "11px");
  }

  _drawLegend() {
    const legendData = [
      { key: "actual", label: "Actual Portfolio", color: this._colors.actual },
      {
        key: "projected",
        label: "Projected",
        color: this._colors.projected,
        isDashed: true,
      },
      {
        key: "required",
        label: "Goal",
        color: this._colors.required,
        isDashed: true,
      },
    ];

    const legend = this._d3Svg
      .append("g")
      .attr("class", "legend")
      .attr(
        "transform",
        `translate(${this._margin.left}, ${this._d3InitialContainerHeight - 20})`
      );

    const legendItems = legend
      .selectAll(".legend-item")
      .data(legendData)
      .join("g")
      .attr("class", "legend-item")
      .attr("transform", (d, i) => `translate(${i * 120}, 0)`);

    legendItems.each(function (d) {
      const item = d3.select(this);
      if (d.isDashed) {
        item
          .append("line")
          .attr("x1", 0)
          .attr("x2", 12)
          .attr("y1", 6)
          .attr("y2", 6)
          .attr("stroke", d.color)
          .attr("stroke-width", 2)
          .attr("stroke-dasharray", "4,2");
      } else {
        item
          .append("rect")
          .attr("width", 12)
          .attr("height", 3)
          .attr("y", 5)
          .attr("rx", 1)
          .attr("fill", d.color);
      }
    });

    legendItems
      .append("text")
      .attr("x", 18)
      .attr("y", 10)
      .attr("fill", "var(--color-gray-600)")
      .style("font-size", "10px")
      .text((d) => d.label);
  }

  _drawTooltip() {
    this._d3Tooltip = d3
      .select(`#${this.element.id}`)
      .append("div")
      .attr(
        "class",
        "bg-container text-sm font-sans absolute p-3 border border-secondary rounded-lg pointer-events-none opacity-0 shadow-lg"
      )
      .style("z-index", "1000");
  }

  _trackMouseForShowingTooltip() {
    const actualData = this.dataValue.series.actual;
    const projectedData = this.dataValue.series.projected;
    const bisectDate = d3.bisector((d) => parseLocalDate(d.date)).left;

    this._d3Group
      .append("rect")
      .attr("class", "overlay")
      .attr("width", this._d3ContainerWidth)
      .attr("height", this._d3ContainerHeight)
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .on("mousemove", (event) => {
        const [xPos] = d3.pointer(event);
        const x0 = this._d3XScale.invert(xPos);
        const i = bisectDate(actualData, x0.toISOString().split("T")[0], 1);
        const idx = Math.min(Math.max(i - 1, 0), actualData.length - 1);

        const actual = actualData[idx];
        const projected = projectedData[idx];

        if (!actual) return;

        // Draw guideline
        this._d3Group.selectAll(".guideline").remove();
        this._d3Group
          .append("line")
          .attr("class", "guideline")
          .attr("x1", this._d3XScale(parseLocalDate(actual.date)))
          .attr("x2", this._d3XScale(parseLocalDate(actual.date)))
          .attr("y1", 0)
          .attr("y2", this._d3ContainerHeight)
          .attr("stroke", "var(--color-gray-400)")
          .attr("stroke-dasharray", "4,4");

        // Position tooltip
        const estimatedTooltipWidth = 220;
        const pageWidth = document.body.clientWidth;
        const tooltipX = event.pageX + 10;
        const overflowX = tooltipX + estimatedTooltipWidth - pageWidth;
        const adjustedX =
          overflowX > 0 ? event.pageX - estimatedTooltipWidth - 10 : tooltipX;

        this._d3Tooltip
          .html(this._tooltipTemplate(actual, projected))
          .style("opacity", 1)
          .style("left", `${adjustedX}px`)
          .style("top", `${event.pageY - 10}px`);
      })
      .on("mouseout", () => {
        this._d3Group.selectAll(".guideline").remove();
        this._d3Tooltip.style("opacity", 0);
      });
  }

  _tooltipTemplate(actual, projected) {
    const formatDate = d3.timeFormat("%B %d, %Y");
    const date = parseLocalDate(actual.date);
    const symbol = this.dataValue.metadata?.currency_symbol || "$";

    let varianceHtml = "";
    if (projected) {
      const variance = actual.value - projected.value;
      const variancePct = ((variance / projected.value) * 100).toFixed(1);
      const isPositive = variance >= 0;
      const color = isPositive
        ? this._colors.variance_positive
        : this._colors.variance_negative;
      const sign = isPositive ? "+" : "";

      varianceHtml = `
        <div style="border-top: 1px solid var(--color-gray-200); padding-top: 6px; margin-top: 6px;">
          <div style="display: flex; justify-content: space-between; gap: 16px;">
            <span>vs Projected</span>
            <span style="font-weight: 600; color: ${color};">
              ${sign}${symbol}${this._formatNumber(Math.abs(variance))} (${sign}${variancePct}%)
            </span>
          </div>
        </div>
      `;
    }

    return `
      <div style="margin-bottom: 8px; font-weight: 600; color: var(--color-gray-700);">
        ${formatDate(date)}
      </div>
      <div style="display: grid; gap: 4px; font-size: 12px;">
        <div style="display: flex; justify-content: space-between; gap: 16px;">
          <span style="display: flex; align-items: center; gap: 6px;">
            <span style="width: 8px; height: 3px; background: ${this._colors.actual}; border-radius: 1px;"></span>
            Actual Portfolio
          </span>
          <span style="font-weight: 600;">${symbol}${this._formatNumber(actual.value)}</span>
        </div>
        ${
          projected
            ? `<div style="display: flex; justify-content: space-between; gap: 16px;">
                <span style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 8px; height: 2px; background: ${this._colors.projected}; border-radius: 1px;"></span>
                  Projected
                </span>
                <span>${symbol}${this._formatNumber(projected.value)}</span>
              </div>`
            : ""
        }
        <div style="display: flex; justify-content: space-between; gap: 16px;">
          <span>Progress</span>
          <span style="font-weight: 500;">${actual.progress_percent}%</span>
        </div>
        ${varianceHtml}
      </div>
    `;
  }

  _formatCurrency(value) {
    const symbol = this.dataValue.metadata?.currency_symbol || "$";
    if (value >= 1000000) {
      return `${symbol}${(value / 1000000).toFixed(1)}M`;
    }
    if (value >= 1000) {
      return `${symbol}${(value / 1000).toFixed(0)}k`;
    }
    return `${symbol}${value.toFixed(0)}`;
  }

  _formatNumber(value) {
    return new Intl.NumberFormat("en-US", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 0,
    }).format(value);
  }

  _createMainSvg() {
    return this._d3Container
      .append("svg")
      .attr("width", this._d3InitialContainerWidth)
      .attr("height", this._d3InitialContainerHeight)
      .attr("viewBox", [
        0,
        0,
        this._d3InitialContainerWidth,
        this._d3InitialContainerHeight,
      ]);
  }

  _createMainGroup() {
    return this._d3Svg
      .append("g")
      .attr(
        "transform",
        `translate(${this._margin.left},${this._margin.top})`
      );
  }

  get _d3Svg() {
    if (!this._d3SvgMemo) {
      this._d3SvgMemo = this._createMainSvg();
    }
    return this._d3SvgMemo;
  }

  get _d3Group() {
    if (!this._d3GroupMemo) {
      this._d3GroupMemo = this._createMainGroup();
    }
    return this._d3GroupMemo;
  }

  get _margin() {
    return { top: 30, right: 20, bottom: 50, left: 70 };
  }

  get _d3ContainerWidth() {
    return (
      this._d3InitialContainerWidth - this._margin.left - this._margin.right
    );
  }

  get _d3ContainerHeight() {
    return (
      this._d3InitialContainerHeight - this._margin.top - this._margin.bottom
    );
  }

  get _d3Container() {
    return d3.select(this.element);
  }

  get _d3XScale() {
    const actualData = this.dataValue.series.actual;
    const currentPoint = this.dataValue.current_point;

    let dates = actualData.map((d) => parseLocalDate(d.date));
    if (currentPoint) {
      dates.push(parseLocalDate(currentPoint.date));
    }

    return d3
      .scaleTime()
      .domain(d3.extent(dates))
      .range([0, this._d3ContainerWidth]);
  }

  get _d3YScale() {
    const actualData = this.dataValue.series.actual;
    const requiredData = this.dataValue.series.required;
    const projectedData = this.dataValue.series.projected;
    const currentPoint = this.dataValue.current_point;

    let allValues = actualData.map((d) => d.value);
    allValues = allValues.concat(requiredData.map((d) => d.value));
    if (projectedData) {
      allValues = allValues.concat(projectedData.map((d) => d.value));
    }
    if (currentPoint) {
      allValues.push(currentPoint.actual_value);
      if (currentPoint.projected_value) {
        allValues.push(currentPoint.projected_value);
      }
    }

    const maxValue = Math.max(...allValues) * 1.1;
    const minValue = Math.min(...allValues) * 0.9;

    return d3
      .scaleLinear()
      .domain([Math.max(0, minValue), maxValue])
      .range([this._d3ContainerHeight, 0]);
  }

  _setupResizeObserver() {
    this._resizeObserver = new ResizeObserver(() => {
      this._reinstall();
    });
    this._resizeObserver.observe(this.element);
  }
}
