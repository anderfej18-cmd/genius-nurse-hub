import { Alert, AlertTitle, AlertDescription } from "@/components/ui/alert";
import { Info } from "lucide-react";

export function OsceDisclaimer({ className }: { className?: string }) {
  return (
    <Alert variant="warning" className={className} icon={Info}>
      <AlertTitle className="text-xs font-semibold tracking-wide uppercase">
        Important: Practice Assessment Only
      </AlertTitle>
      <AlertDescription className="text-xs flex flex-col gap-1.5 mt-1 text-muted-foreground [text-wrap:pretty]">
        <p>
          This assessment evaluates your ability to verbally explain the steps of a nursing
          procedure. It does not assess or verify your physical performance.
        </p>
        <p>
          During your actual clinical OSCE examination, you are required to physically demonstrate
          the procedures and perform the required steps correctly, in addition to explaining them
          when requested.
        </p>
        <p className="font-medium text-foreground">
          Verbalising a procedure during this practice session does not replace physically
          performing it during the real examination.
        </p>
      </AlertDescription>
    </Alert>
  );
}
