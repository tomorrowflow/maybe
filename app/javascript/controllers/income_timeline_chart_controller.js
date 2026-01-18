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

  // Color scheme for income sources
  _colors = {
    salary: "#3B82F6", // blue
    state_pension: "#22C55E", // green
    private_pensions: "#8B5CF6", // purple
    other: "#F97316", // orange
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
    const series = this.dataValue.series;
    if (!series || !series.salary || series.salary.length < 2) {
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
      .text("Not enough data to display timeline");
  }

  _drawChart() {
    this._drawGapPeriodHighlight();
    this._drawStackedAreas();
    this._drawExpensesLine();
    this._drawMilestoneMarkers();
    this._drawAxes();
    this._drawLegend();
    this._drawTooltip();
    this._trackMouseForShowingTooltip();
  }

  _drawGapPeriodHighlight() {
    const gap = this.dataValue.gap_period;
    if (!gap) return;

    const gapStart = parseLocalDate(gap.start_date);
    const gapEnd = parseLocalDate(gap.end_date);

    if (!gapStart || !gapEnd) return;

    this._d3Group
      .append("rect")
      .attr("class", "gap-period-highlight")
      .attr("x", this._d3XScale(gapStart))
      .attr("y", 0)
      .attr("width", this._d3XScale(gapEnd) - this._d3XScale(gapStart))
      .attr("height", this._d3ContainerHeight)
      .attr("fill", "#FEF3C7")
      .attr("opacity", 0.5);

    // Gap label
    const gapMidX =
      (this._d3XScale(gapStart) + this._d3XScale(gapEnd)) / 2;
    this._d3Group
      .append("text")
      .attr("x", gapMidX)
      .attr("y", 20)
      .attr("text-anchor", "middle")
      .attr("fill", "#92400E")
      .style("font-size", "11px")
      .style("font-weight", "600")
      .text(`Gap: ${gap.months} months`);
  }

  _drawStackedAreas() {
    const series = this.dataValue.series;
    const keys = ["salary", "state_pension", "private_pensions", "other"];

    // Transform data for stacking
    const stackData = series.salary.map((d, i) => ({
      date: parseLocalDate(d.date),
      salary: series.salary[i]?.value || 0,
      state_pension: series.state_pension[i]?.value || 0,
      private_pensions: series.private_pensions[i]?.value || 0,
      other: series.other[i]?.value || 0,
    }));

    const stack = d3.stack().keys(keys).order(d3.stackOrderNone);
    const stackedData = stack(stackData);

    const area = d3
      .area()
      .x((d) => this._d3XScale(d.data.date))
      .y0((d) => this._d3YScale(d[0]))
      .y1((d) => this._d3YScale(d[1]))
      .curve(d3.curveMonotoneX);

    this._d3Group
      .selectAll(".income-area")
      .data(stackedData)
      .join("path")
      .attr("class", "income-area")
      .attr("d", area)
      .attr("fill", (d) => this._colors[d.key])
      .attr("opacity", 0.8);
  }

  _drawExpensesLine() {
    const expensesData = this.dataValue.expenses_line;
    if (!expensesData || expensesData.length === 0) return;

    const lineData = expensesData.map((d) => ({
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
      .attr("class", "expenses-line")
      .attr("fill", "none")
      .attr("stroke", "#EF4444")
      .attr("stroke-width", 2)
      .attr("stroke-dasharray", "6,4")
      .attr("d", line);
  }

  _drawMilestoneMarkers() {
    const milestones = this.dataValue.milestones;
    if (!milestones || milestones.length === 0) return;

    const visibleMilestones = milestones.filter((m) => {
      const date = parseLocalDate(m.date);
      const [minDate, maxDate] = this._d3XScale.domain();
      return date >= minDate && date <= maxDate;
    });

    // Draw vertical lines for milestones
    this._d3Group
      .selectAll(".milestone-line")
      .data(visibleMilestones)
      .join("line")
      .attr("class", "milestone-line")
      .attr("x1", (d) => this._d3XScale(parseLocalDate(d.date)))
      .attr("x2", (d) => this._d3XScale(parseLocalDate(d.date)))
      .attr("y1", 0)
      .attr("y2", this._d3ContainerHeight)
      .attr("stroke", (d) => this._getMilestoneColor(d.type))
      .attr("stroke-width", 1.5)
      .attr("stroke-dasharray", "4,2")
      .attr("opacity", 0.7);

    // Draw milestone dots at top
    this._d3Group
      .selectAll(".milestone-dot")
      .data(visibleMilestones)
      .join("circle")
      .attr("class", "milestone-dot")
      .attr("cx", (d) => this._d3XScale(parseLocalDate(d.date)))
      .attr("cy", 10)
      .attr("r", 5)
      .attr("fill", (d) => this._getMilestoneColor(d.type))
      .attr("stroke", "#fff")
      .attr("stroke-width", 1.5);
  }

  _getMilestoneColor(type) {
    const colors = {
      salary_end: "#EF4444",
      state_pension_start: "#22C55E",
      private_pension_start: "#8B5CF6",
      other_pension_start: "#F97316",
      gap_start: "#F59E0B",
      gap_end: "#F59E0B",
    };
    return colors[type] || "#6B7280";
  }

  _drawAxes() {
    // X Axis
    const xAxisGroup = this._d3Group
      .append("g")
      .attr("transform", `translate(0,${this._d3ContainerHeight})`)
      .call(
        d3
          .axisBottom(this._d3XScale)
          .ticks(6)
          .tickFormat(d3.timeFormat("%Y"))
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
      { key: "salary", label: "Salary" },
      { key: "state_pension", label: "State Pension" },
      { key: "private_pensions", label: "Private Pensions" },
      { key: "other", label: "Other" },
      { key: "expenses", label: "Expenses", isDashed: true },
    ];

    const legend = this._d3Svg
      .append("g")
      .attr("class", "legend")
      .attr("transform", `translate(${this._margin.left}, ${this._d3InitialContainerHeight - 20})`);

    const legendItems = legend
      .selectAll(".legend-item")
      .data(legendData)
      .join("g")
      .attr("class", "legend-item")
      .attr("transform", (d, i) => `translate(${i * 100}, 0)`);

    legendItems
      .append("rect")
      .attr("width", 12)
      .attr("height", (d) => (d.isDashed ? 2 : 12))
      .attr("y", (d) => (d.isDashed ? 5 : 0))
      .attr("fill", (d) => (d.key === "expenses" ? "#EF4444" : this._colors[d.key]));

    legendItems
      .append("text")
      .attr("x", 16)
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
    const series = this.dataValue.series;
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
        const i = bisectDate(series.salary, x0.toISOString().split("T")[0], 1);
        const idx = Math.min(Math.max(i - 1, 0), series.salary.length - 1);

        const d = {
          date: series.salary[idx].date,
          salary: series.salary[idx]?.value || 0,
          state_pension: series.state_pension[idx]?.value || 0,
          private_pensions: series.private_pensions[idx]?.value || 0,
          other: series.other[idx]?.value || 0,
          expenses: this.dataValue.expenses_line[idx]?.value || 0,
        };

        const totalIncome =
          d.salary + d.state_pension + d.private_pensions + d.other;

        // Update guideline
        this._d3Group.selectAll(".guideline").remove();
        this._d3Group
          .append("line")
          .attr("class", "guideline")
          .attr("x1", xPos)
          .attr("x2", xPos)
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
          .html(this._tooltipTemplate(d, totalIncome))
          .style("opacity", 1)
          .style("left", `${adjustedX}px`)
          .style("top", `${event.pageY - 10}px`);
      })
      .on("mouseout", () => {
        this._d3Group.selectAll(".guideline").remove();
        this._d3Tooltip.style("opacity", 0);
      });
  }

  _tooltipTemplate(d, totalIncome) {
    const formatDate = d3.timeFormat("%B %Y");
    const date = parseLocalDate(d.date);
    const symbol = this.dataValue.metadata?.currency_symbol || "$";

    return `
      <div style="margin-bottom: 8px; font-weight: 600; color: var(--color-gray-700);">
        ${formatDate(date)}
      </div>
      <div style="display: grid; gap: 4px; font-size: 12px;">
        ${
          d.salary > 0
            ? `<div style="display: flex; justify-content: space-between; gap: 16px;">
                <span style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 8px; height: 8px; background: ${this._colors.salary}; border-radius: 2px;"></span>
                  Salary
                </span>
                <span style="font-weight: 500;">${symbol}${this._formatNumber(d.salary)}</span>
              </div>`
            : ""
        }
        ${
          d.state_pension > 0
            ? `<div style="display: flex; justify-content: space-between; gap: 16px;">
                <span style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 8px; height: 8px; background: ${this._colors.state_pension}; border-radius: 2px;"></span>
                  State Pension
                </span>
                <span style="font-weight: 500;">${symbol}${this._formatNumber(d.state_pension)}</span>
              </div>`
            : ""
        }
        ${
          d.private_pensions > 0
            ? `<div style="display: flex; justify-content: space-between; gap: 16px;">
                <span style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 8px; height: 8px; background: ${this._colors.private_pensions}; border-radius: 2px;"></span>
                  Private Pensions
                </span>
                <span style="font-weight: 500;">${symbol}${this._formatNumber(d.private_pensions)}</span>
              </div>`
            : ""
        }
        ${
          d.other > 0
            ? `<div style="display: flex; justify-content: space-between; gap: 16px;">
                <span style="display: flex; align-items: center; gap: 6px;">
                  <span style="width: 8px; height: 8px; background: ${this._colors.other}; border-radius: 2px;"></span>
                  Other
                </span>
                <span style="font-weight: 500;">${symbol}${this._formatNumber(d.other)}</span>
              </div>`
            : ""
        }
        <div style="border-top: 1px solid var(--color-gray-200); margin-top: 4px; padding-top: 4px; display: flex; justify-content: space-between; gap: 16px;">
          <span style="font-weight: 600;">Total Income</span>
          <span style="font-weight: 600;">${symbol}${this._formatNumber(totalIncome)}</span>
        </div>
        <div style="display: flex; justify-content: space-between; gap: 16px; color: ${totalIncome >= d.expenses ? "var(--color-green-600)" : "var(--color-red-600)"};">
          <span>vs Expenses</span>
          <span style="font-weight: 500;">${symbol}${this._formatNumber(d.expenses)}</span>
        </div>
      </div>
    `;
  }

  _formatCurrency(value) {
    const symbol = this.dataValue.metadata?.currency_symbol || "$";
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
      .attr("transform", `translate(${this._margin.left},${this._margin.top})`);
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
    return { top: 30, right: 20, bottom: 50, left: 60 };
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
    const series = this.dataValue.series;
    const dates = series.salary.map((d) => parseLocalDate(d.date));
    return d3
      .scaleTime()
      .domain(d3.extent(dates))
      .range([0, this._d3ContainerWidth]);
  }

  get _d3YScale() {
    const series = this.dataValue.series;
    const expenses = this.dataValue.expenses_line || [];

    // Calculate max stacked value
    let maxStacked = 0;
    for (let i = 0; i < series.salary.length; i++) {
      const total =
        (series.salary[i]?.value || 0) +
        (series.state_pension[i]?.value || 0) +
        (series.private_pensions[i]?.value || 0) +
        (series.other[i]?.value || 0);
      maxStacked = Math.max(maxStacked, total);
    }

    // Consider expenses line too
    const maxExpenses = d3.max(expenses, (d) => d.value) || 0;
    const maxValue = Math.max(maxStacked, maxExpenses) * 1.1;

    return d3
      .scaleLinear()
      .domain([0, maxValue])
      .range([this._d3ContainerHeight, 0]);
  }

  _setupResizeObserver() {
    this._resizeObserver = new ResizeObserver(() => {
      this._reinstall();
    });
    this._resizeObserver.observe(this.element);
  }
}
