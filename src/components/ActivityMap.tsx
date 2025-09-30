import React from "react";
import { ActivityMapProps } from "../types/activityMap";
import { getYearDays, processActivityData } from "../lib/activityMapHelpers";
import ActivityGrid from "./ActivityGrid";

const ActivityMap: React.FC<ActivityMapProps> = ({ rowsData }) => {
  const activity = processActivityData(rowsData); // Process timestamps into date counts

  const days = getYearDays(new Date()); // Get 52 weeks of days
  const weeks: string[][] = [];
  for (let i = 0; i < days.length; i += 7) {
    // Group days into weeks
    weeks.push(days.slice(i, i + 7));
  }
  weeks.reverse(); // Reverse to start from most recent weeks

  return (
    <div>
      <h3 className="mb-2 font-bold">Activity Map (52 Weeks)</h3>
      <ActivityGrid weeks={weeks} activity={activity} />
    </div>
  );
};

export default ActivityMap;
