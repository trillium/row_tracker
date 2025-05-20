import { RowingStats } from "../components/RowingStats";

export default async function Home() {
  return (
    <div className="flex flex-col gap-8 items-center justify-center max-w-screen">
      <RowingStats />
    </div>
  );
}
