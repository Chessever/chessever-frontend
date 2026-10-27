import { Minus, Plus } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

interface ZoomControlsProps {
  zoom: number;
  onZoomIn: () => void;
  onZoomOut: () => void;
  onReset: () => void;
}

export function ZoomControls({
  zoom,
  onZoomIn,
  onZoomOut,
  onReset,
}: ZoomControlsProps) {
  return (
    <Card className="pointer-events-auto flex-row items-center gap-0.5 rounded-lg p-1 backdrop-blur-md bg-neutral-900/90 border border-border/5 shadow-lg">
      <Button variant="ghost" size="icon" className="size-7" onClick={onZoomOut} aria-label="Zoom out">
        <Minus />
      </Button>
      <button
        onClick={onReset}
        title="Reset view"
        className="min-w-14 rounded-md px-1 py-1 text-center font-mono text-xs tabular-nums text-muted-foreground transition-colors hover:text-foreground"
      >
        {Math.round(zoom * 100)}%
      </button>
      <Button variant="ghost" size="icon" className="size-7" onClick={onZoomIn} aria-label="Zoom in">
        <Plus />
      </Button>
    </Card>
  );
}
