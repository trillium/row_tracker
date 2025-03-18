import Image from "next/image";
import { countLines } from "../lib/countLines";
//import Activity from "@/components/activity";

function getDaysDifference(date1: Date, date2: Date): number {
  const timeDifference = date1.getTime() - date2.getTime();
  return Math.ceil(timeDifference / (1000 * 3600 * 24));
}

function getDaysPassedThisYear(today = new Date()): number {
  const currentYear = today.getFullYear();
  const startOfYear = new Date(currentYear, 0, 1);
  return getDaysDifference(today, startOfYear);
}

export default async function Home() {
  const today = new Date();
  const rows = await countLines();

  const daysPassedThisYear = getDaysPassedThisYear(today);

  return (
    <div className="grid grid-rows-[1fr_1fr_1fr] items-center justify-items-center min-h-screen p-8 pb-20 gap-16 sm:p-20 font-[family-name:var(--font-geist-sans)]">
      <main className="flex flex-col gap-8 row-start-2 items-center justify-center max-w-screen">
        {/* <Activity rows={rows} daysPassedThisYear={daysPassedThisYear} /> */}

        <div className="flex flex-col items-start border border-red-500 p-4">
          <p>{`Days passed this year: ${daysPassedThisYear}`}</p>
          <p>{`Rows this year: ${rows}`}</p>
          {daysPassedThisYear - rows <= 0 && (
            <p className="text-green-500 text-2xl">{`Rows ahead: +${
              daysPassedThisYear - rows
            }`}</p>
          )}
          {daysPassedThisYear - rows > 0 && (
            <p className="text-red-500 text-2xl">{`Rows behind: -${
              daysPassedThisYear - rows
            }`}</p>
          )}
        </div>
      </main>
      <Footer />
    </div>
  );
}

async function Footer() {
  return (
    <footer className="row-start-3 flex gap-6 flex-wrap items-center justify-center">
      <a
        className="flex items-center gap-2 hover:underline hover:underline-offset-4"
        href="https://nextjs.org/learn?utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
        target="_blank"
        rel="noopener noreferrer"
      >
        <Image
          aria-hidden
          src="/file.svg"
          alt="File icon"
          width={16}
          height={16}
        />
        Learn
      </a>
      <a
        className="flex items-center gap-2 hover:underline hover:underline-offset-4"
        href="https://vercel.com/templates?framework=next.js&utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
        target="_blank"
        rel="noopener noreferrer"
      >
        <Image
          aria-hidden
          src="/window.svg"
          alt="Window icon"
          width={16}
          height={16}
        />
        Examples
      </a>
      <a
        className="flex items-center hover:underline hover:underline-offset-4"
        href="https://nextjs.org?utm_source=create-next-app&utm_medium=appdir-template-tw&utm_campaign=create-next-app"
        target="_blank"
        rel="noopener noreferrer"
      >
        <Image
          aria-hidden
          src="/globe.svg"
          alt="Globe icon"
          width={16}
          height={16}
        />
        Go to nextjs.org →
      </a>
    </footer>
  );
}
