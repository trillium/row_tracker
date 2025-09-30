import React from "react";
import Week from "./Week";

interface ActivityGridProps {
  weeks: string[][];
  activity: { [date: string]: number };
}

const ActivityGrid: React.FC<ActivityGridProps> = ({ weeks, activity }) => {
  return (
    <div className="flex">
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
        return <Week key={wi} week={week} activity={activity} weekIndex={wi} />;
      })}
    </div>
  );
};

export default ActivityGrid;
