import { RowingStats } from "../components/RowingStats";
import ActivityMap from "../components/ActivityMap";
import { readFile } from "fs/promises";
import { join } from "path";

export default async function Home() {
  // Read the rows.txt file and parse into array of timestamps
  const rowsFilePath = join(process.cwd(), "rows.txt");
  const rowsContent = await readFile(rowsFilePath, "utf-8");
  const rowsData = rowsContent.split("\n").filter((line) => line.trim());

  return (
    <div className="flex flex-col gap-8 overflow-x-auto">
      <RowingStats />
      <ActivityMap rowsData={rowsData} />
    </div>
  );
}
