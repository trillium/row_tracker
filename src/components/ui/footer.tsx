import Link from "next/link";

export default function Footer() {
  return (
    <footer className="row-start-3 flex gap-6 flex-wrap items-center justify-center">
      <p>
        This website made by Trillium{" "}
        <Link
          className="font-bold text-primary-500 underline"
          href="while_rowing"
        >
          while rowing
        </Link>
        .
      </p>
    </footer>
  );
}
