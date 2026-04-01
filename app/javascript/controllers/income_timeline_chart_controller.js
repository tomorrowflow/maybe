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
    this._drawSavingsLine();
    this._drawMilestoneMarkers();
    this._drawAxes();
    this._drawLegend();
    this._drawTooltip();
    // Tooltip tracking must be last so the overlay is on top of milestone hover areas
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
    const keys = ["salary", "private_pensions", "other"];

    // Transform data for stacking
    const stackData = series.salary.map((d, i) => ({
      date: parseLocalDate(d.date),
      salary: series.salary[i]?.value || 0,
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

  _drawSavingsLine() {
    const savingsData = this.dataValue.savings_line;
    if (!savingsData || savingsData.length === 0) return;

    const lineData = savingsData.map((d) => ({
      date: parseLocalDate(d.date),
      value: d.value,
    })).filter(d => d.date != null);

    if (lineData.length < 2) return;

    // Secondary y-axis scale for savings (right side)
    const maxSavings = d3.max(lineData, (d) => d.value) || 1;
    const savingsScale = d3.scaleLinear()
      .domain([0, maxSavings * 1.1])
      .range([this._d3ContainerHeight, 0]);

    const line = d3.line()
      .x((d) => this._d3XScale(d.date))
      .y((d) => savingsScale(d.value))
      .curve(d3.curveMonotoneX);

    // Draw savings area (light fill)
    const area = d3.area()
      .x((d) => this._d3XScale(d.date))
      .y0(this._d3ContainerHeight)
      .y1((d) => savingsScale(d.value))
      .curve(d3.curveMonotoneX);

    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("class", "savings-area")
      .attr("fill", "rgba(16, 185, 129, 0.08)")
      .attr("d", area);

    // Draw savings line
    this._d3Group
      .append("path")
      .datum(lineData)
      .attr("class", "savings-line")
      .attr("fill", "none")
      .attr("stroke", "#10B981")
      .attr("stroke-width", 2)
      .attr("d", line);

    // Right y-axis for savings
    const rightAxis = this._d3Group.append("g")
      .attr("transform", `translate(${this._d3ContainerWidth}, 0)`)
      .call(d3.axisRight(savingsScale).ticks(4).tickFormat((d) => this._formatCurrency(d)));

    rightAxis.select(".domain").attr("stroke", "#10B981").attr("opacity", 0.3);
    rightAxis.selectAll(".tick line").attr("stroke", "#10B981").attr("opacity", 0.3);
    rightAxis.selectAll(".tick text")
      .attr("fill", "#10B981")
      .style("font-size", "10px");

    // Store savings scale for tooltip
    this._savingsScale = savingsScale;
    this._savingsData = lineData;
  }

  // Placeholder to prevent the original expenses line from drawing twice
  _drawExpensesLineOriginal() {
    // This method exists only to maintain the pattern
  }
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
      .attr("opacity", 0.5);

    // Draw milestone dots
    this._d3Group
      .selectAll(".milestone-dot")
      .data(visibleMilestones)
      .join("circle")
      .attr("class", "milestone-dot")
      .attr("cx", (d) => this._d3XScale(parseLocalDate(d.date)))
      .attr("cy", 8)
      .attr("r", 4)
      .attr("fill", (d) => this._getMilestoneColor(d.type))
      .attr("stroke", "#fff")
      .attr("stroke-width", 1.5);

    // Draw milestone labels with background
    const labelGroups = this._d3Group
      .selectAll(".milestone-label-group")
      .data(visibleMilestones)
      .join("g")
      .attr("class", "milestone-label-group")
      .attr("transform", (d, i) => {
        const x = this._d3XScale(parseLocalDate(d.date));
        const y = 20 + (i % 3) * 14; // Stagger labels to avoid overlap
        return `translate(${x}, ${y})`;
      });

    // Label background
    labelGroups.each(function(d) {
      const label = d.label || "";
      const textWidth = label.length * 5 + 12;
      d3.select(this)
        .append("rect")
        .attr("x", 4)
        .attr("y", -8)
        .attr("width", textWidth)
        .attr("height", 14)
        .attr("rx", 3)
        .attr("fill", "var(--color-container, #fff)")
        .attr("stroke", "var(--color-alpha-black-100, #e5e5e5)")
        .attr("stroke-width", 0.5)
        .attr("opacity", 0.95);
    });

    // Label text
    labelGroups
      .append("text")
      .attr("x", 8)
      .attr("y", 3)
      .attr("fill", (d) => this._getMilestoneColor(d.type))
      .style("font-size", "9px")
      .style("font-weight", "600")
      .text((d) => d.label || "");

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
      { key: "private_pensions", label: "Pensions" },
      { key: "other", label: "Part-time Work" },
      { key: "expenses", label: "Expenses", isDashed: true },
      { key: "savings", label: "Savings (right axis)", color: "#10B981" },
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
      .attr("fill", (d) => d.color || (d.key === "expenses" ? "#EF4444" : this._colors[d.key]));

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

        // Find savings value at this date (yearly data, find nearest year)
        const savingsLine = this.dataValue.savings_line || [];
        const monthIndex = idx;
        const yearIndex = Math.round(monthIndex / 12);
        const savingsValue = savingsLine[yearIndex]?.value || 0;

        const d = {
          date: series.salary[idx].date,
          salary: series.salary[idx]?.value || 0,
          private_pensions: series.private_pensions[idx]?.value || 0,
          other: series.other[idx]?.value || 0,
          expenses: this.dataValue.expenses_line[idx]?.value || 0,
          savings: savingsValue,
        };

        const totalIncome = d.salary + d.private_pensions + d.other;
        const surplus = totalIncome - d.expenses;

        // Find milestones near this date (within 45 days)
        const milestones = (this.dataValue.milestones || []).filter((m) => {
          const mDate = parseLocalDate(m.date);
          const diff = Math.abs(x0 - mDate);
          return diff < 45 * 86400000; // 45 days in ms
        });

        // Highlight nearby milestone lines
        this._d3Group.selectAll(".milestone-line")
          .attr("stroke-width", 1.5)
          .attr("opacity", 0.5);
        milestones.forEach((m) => {
          this._d3Group.selectAll(".milestone-line")
            .filter(ml => ml.date === m.date && ml.type === m.type)
            .attr("stroke-width", 3)
            .attr("opacity", 1);
        });

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

        // Position tooltip relative to the chart container
        const containerRect = this.element.getBoundingClientRect();
        const relX = event.clientX - containerRect.left;
        const relY = event.clientY - containerRect.top;
        const estimatedTooltipWidth = 220;
        const adjustedX = relX + estimatedTooltipWidth > containerRect.width
          ? relX - estimatedTooltipWidth - 10
          : relX + 12;

        this._d3Tooltip
          .html(this._tooltipTemplate(d, totalIncome, milestones))
          .style("opacity", 1)
          .style("left", `${adjustedX}px`)
          .style("top", `${Math.max(relY - 10, 0)}px`);
      })
      .on("mouseout", () => {
        this._d3Group.selectAll(".guideline").remove();
        this._d3Tooltip.style("opacity", 0);
        this._d3Group.selectAll(".milestone-line")
          .attr("stroke-width", 1.5)
          .attr("opacity", 0.5);
      });
  }

  _tooltipTemplate(d, totalIncome, milestones = []) {
    const formatDate = d3.timeFormat("%B %Y");
    const date = parseLocalDate(d.date);
    const symbol = this.dataValue.metadata?.currency_symbol || "€";
    const surplus = totalIncome - d.expenses;

    const row = (color, label, value) => `
      <div style="display: flex; justify-content: space-between; gap: 20px;">
        <span style="display: flex; align-items: center; gap: 6px;">
          ${color ? `<span style="width: 8px; height: 8px; background: ${color}; border-radius: 2px;"></span>` : ""}
          ${label}
        </span>
        <span style="font-weight: 500; white-space: nowrap;">${value}</span>
      </div>`;

    const separator = `<div style="border-top: 1px solid var(--color-gray-200); margin: 4px 0;"></div>`;

    let html = `<div style="margin-bottom: 6px; font-weight: 600; color: var(--color-gray-700);">${formatDate(date)}</div>`;
    html += `<div style="display: grid; gap: 3px; font-size: 12px;">`;

    // Income section
    if (d.salary > 0) html += row(this._colors.salary, "Salary", `${symbol}${this._formatNumber(d.salary)}`);
    if (d.private_pensions > 0) html += row(this._colors.private_pensions, "Pensions", `${symbol}${this._formatNumber(d.private_pensions)}`);
    if (d.other > 0) html += row(this._colors.other, "Part-time Work", `${symbol}${this._formatNumber(d.other)}`);

    html += separator;
    html += row(null, "<strong>Total Income</strong>", `<strong>${symbol}${this._formatNumber(totalIncome)}</strong>`);

    // Expenses
    html += separator;
    html += row(null, `<span style="color: #EF4444;">Expenses</span>`, `<span style="color: #EF4444;">${symbol}${this._formatNumber(d.expenses)}</span>`);

    // Surplus / Deficit
    html += separator;
    const surplusColor = surplus >= 0 ? "var(--color-green-600)" : "var(--color-red-600)";
    const surplusSign = surplus >= 0 ? "+" : "";
    html += row(null,
      `<strong style="color: ${surplusColor};">${surplus >= 0 ? "Surplus" : "Deficit"}</strong>`,
      `<strong style="color: ${surplusColor};">${surplusSign}${symbol}${this._formatNumber(surplus)}</strong>`
    );

    // Savings balance
    if (d.savings > 0) {
      html += separator;
      html += row(null,
        `<span style="color: #10B981;">Savings Balance</span>`,
        `<span style="color: #10B981; font-weight: 600;">${symbol}${this._formatNumber(d.savings)}</span>`
      );
    }

    // Milestones near this date
    if (milestones.length > 0) {
      html += separator;
      milestones.forEach((m) => {
        const color = this._getMilestoneColor(m.type);
        const amountStr = m.amount ? `${symbol}${this._formatNumber(Math.abs(m.amount))}/mo` : "";
        html += `<div style="display: flex; align-items: start; gap: 6px;">
          <span style="width: 8px; height: 8px; background: ${color}; border-radius: 50%; margin-top: 4px; flex-shrink: 0;"></span>
          <span style="color: ${color}; font-weight: 500;">${m.label}${amountStr ? ` (${amountStr})` : ""}</span>
        </div>`;
      });
    }

    html += `</div>`;
    return html;
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
