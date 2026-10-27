import { Pause, Play } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Slider } from "@/components/ui/slider";

interface PlaybackControlsProps {
  playing: boolean;
  currentFrame: number;
  totalFrames: number;
  fps: number;
  onToggle: () => void;
  onSeek: (frame: number) => void;
}

export function PlaybackControls({
  playing,
  currentFrame,
  totalFrames,
  fps,
  onToggle,
  onSeek,
}: PlaybackControlsProps) {
  const max = Math.max(0, totalFrames - 1);
  const frame = Math.min(Math.round(currentFrame), max);
  const pad = String(max).length;

  return (
    <Card className="pointer-events-auto w-full max-w-xl gap-0 py-2 backdrop-blur-md bg-neutral-900/90 border border-border/5 shadow-lg">
      <CardContent className="flex items-center p-0 h-full px-2 gap-3">
        <Button
          size="icon"
          onClick={onToggle}
          aria-label={playing ? "Pause" : "Play"}
          className="size-7 rounded-sm"
        >
          {playing ? <Pause /> : <Play />}
        </Button>

        <Slider
          className="flex-1"
          min={0}
          max={max || 1}
          step={1}
          value={[frame]}
          onValueChange={([v]) => onSeek(v)}
          aria-label="Seek"
        />

        <div className="shrink-0 text-right font-mono text-xs tabular-nums text-muted-foreground flex items-center gap-2">
          <span>
            <span className="text-foreground">{String(frame).padStart(pad, "0")}</span>
            {" / "}
            {max}
          </span>
          <div className="h-6 w-px bg-muted-foreground/15" />
          <span className="text-muted-foreground/70 pr-2">{fps}FPS</span>
        </div>
      </CardContent>
    </Card>
  );
}
