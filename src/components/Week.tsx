import React from "react";
import DayCell from "./DayCell";
import clsx from "clsx";

interface WeekProps {
  week: string[];
  activity: { [date: string]: number };
  weekIndex: number;
  untracked: {
    count: number;
    date: string | null;
  };
  isFirstUntrackedWeek: boolean;
  monthLabel: string | null;
}

const Week: React.FC<WeekProps> = ({
  week,
  activity,
  untracked,
  isFirstUntrackedWeek,
  monthLabel,
}) => {
  const totalActivities = week.reduce(
    (sum, day) => sum + (activity[day] || 0),
    0
  );

  // Check if week should have red background
  const shouldHighlight =
    untracked.date &&
    !week.includes(untracked.date) &&
    week[0] < untracked.date;

  // Determine header text
  const headerText = isFirstUntrackedWeek
    ? `Untracked count: ${untracked.count}`
    : totalActivities > 0
    ? totalActivities.toString()
    : "";

  return (
    <div className={clsx("flex flex-col", { "bg-teal-100 dark:bg-teal-900": shouldHighlight })}>
      {/* Week header */}
      <div
        className={clsx(
          "w-3 h-3 m-0.5 flex items-center text-xs text-slate-600 dark:text-slate-400 font-bold rotate-[-45deg] underline whitespace-nowrap",
          isFirstUntrackedWeek
            ? "justify-start translate-x-[-10px] translate-y-[2px]"
            : "justify-center translate-x-[2px] translate-y-[2px]"
        )}
      >
        <span
          className={clsx({
            "bg-teal-100 dark:bg-teal-900 p-1 rounded-md border border-teal-300 dark:border-gray-700":
              isFirstUntrackedWeek,
          })}
        >
          {headerText}
        </span>
      </div>
      {/* Week column */}
      {week.map((day, di) => {
        const count = activity[day] || 0;
        return <DayCell key={di} dateStr={day} count={count} />;
      })}
      {/* Month label */}
      {monthLabel && (
        <div className="w-3 h-3 m-0.5 flex items-center justify-center text-xs text-slate-600 dark:text-slate-400 font-bold rotate-[-45deg]">
          {monthLabel}
        </div>
      )}
    </div>
  );
};

export default Week;
