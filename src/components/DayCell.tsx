import clsx from "clsx";
import React from "react";

interface DayCellProps {
  dateStr: string;
  count: number;
}

const DayCell: React.FC<DayCellProps> = ({ dateStr, count }) => {
  const isFuture = new Date(dateStr) > new Date();
  return (
    <div
      title={!isFuture ? `${dateStr}: ${count} activities` : undefined} // Tooltip
      className={clsx(
        "w-3 h-3 m-0.5 rounded-sm border flex items-center justify-center",
        {
          "bg-black border-black text-black": isFuture,
          "bg-teal-500 border-white text-teal-600": count === 6,
          "bg-teal-500 border-teal-100 text-teal-600": count === 5,
          "bg-teal-500 border-teal-400 text-teal-600": count === 4,
          "bg-teal-600 border-slate-800 text-teal-700": count === 3,
          "bg-teal-700 border-slate-800 text-teal-900": count === 2,
          "bg-teal-800 border-slate-800 text-teal-900": count === 1,
          "bg-slate-950 border-slate-800 text-slate-800": count === 0,
        }
      )}
    >
      <span>{count > 0 ? count : ""}</span>
    </div>
  );
};

export default DayCell;
