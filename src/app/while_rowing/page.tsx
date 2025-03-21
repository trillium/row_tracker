import Footer from "@/components/ui/footer";

export default async function Home() {
  return (
    <div className="grid grid-rows-[1fr_1fr_1fr] items-center justify-items-center min-h-screen p-8 pb-20 gap-16 sm:p-20 font-[family-name:var(--font-geist-sans)]">
      <main className="flex flex-col gap-8 row-start-2 items-center justify-center max-w-screen">
        <div className="">
          <p>Under construction.</p>
        </div>
      </main>
      <Footer />
    </div>
  );
}
