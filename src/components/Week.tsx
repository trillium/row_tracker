import React from "react";
import DayCell from "./DayCell";

interface WeekProps {
  week: string[];
  activity: { [date: string]: number };
  weekIndex: number;
}

const Week: React.FC<WeekProps> = ({ week, activity }) => {
  const totalActivities = week.reduce(
    (sum, day) => sum + (activity[day] || 0),
    0
  );
  return (
    <div className="flex flex-col">
      {/* Week header */}
      <div className="w-3 h-3 m-0.5 flex items-center justify-center text-xs text-slate-400 font-bold rotate-[-45deg] translate-x-[2px] translate-y-[2px] underline">
        {totalActivities > 0 ? totalActivities : ""}
      </div>
      {/* Week column */}
      {week.map((day, di) => {
        const count = activity[day] || 0;
        return <DayCell key={di} dateStr={day} count={count} />;
      })}
    </div>
  );
};

export default Week;
