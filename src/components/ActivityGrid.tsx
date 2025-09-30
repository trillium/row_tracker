import React from "react";
import Week from "./Week";

interface ActivityGridProps {
  weeks: string[][];
  activity: { [date: string]: number };
  untracked: {
    count: number;
    date: string | null;
  };
}

const ActivityGrid: React.FC<ActivityGridProps> = ({
  weeks,
  activity,
  untracked,
}) => {
  // Find the first week that should be highlighted (before untracked.date and doesn't contain it)
  let firstUntrackedWeekIndex = -1;
  for (let i = 0; i < weeks.length; i++) {
    const week = weeks[i];
    const shouldHighlight =
      untracked.date &&
      !week.includes(untracked.date) &&
      week[0] < untracked.date;
    if (shouldHighlight) {
      firstUntrackedWeekIndex = i;
      break;
    }
  }

  // Calculate month labels
  const monthLabels: (string | null)[] = [];
  const seenMonths = new Set<string>();
  for (let wi = 0; wi < weeks.length; wi++) {
    const week = weeks[wi];
    let monthLabel: string | null = null;
    for (const day of week) {
      const date = new Date(day);
      if (date.getDate() === 1) {
        const month = date.toLocaleString("en-US", { month: "short" });
        if (!seenMonths.has(month)) {
          seenMonths.add(month);
          monthLabel = month;
          break;
        }
      }
    }
    monthLabels[wi] = monthLabel;
  }

  return (
    <div className="flex border border-teal-950 rounded-lg">
      {/* Day headings */}
      <div className="flex flex-col mr-2">
        <div className="w-3 h-3 m-0.5"></div>
        {["S", "M", "T", "W", "T", "F", "S"].map((day, i) => (
          <div
            key={i}
            className="w-3 h-3 m-0.5 flex items-center justify-center text-xs text-slate-400 font-bold"
          >
            {day}
          </div>
        ))}
      </div>
      {/* Flex container for weeks */}
      {weeks.map((week, wi) => {
        return (
          <Week
            key={wi}
            week={week}
            activity={activity}
            weekIndex={wi}
            untracked={untracked}
            isFirstUntrackedWeek={wi === firstUntrackedWeekIndex}
            monthLabel={monthLabels[wi]}
          />
        );
      })}
    </div>
  );
};

export default ActivityGrid;
