# Free pretrained chess photo-to-FEN models: licence and commercial-use research

Date: 2026-10-14. Sources: primary only - official GitHub repos and their `LICENSE`
files, paper pages, dataset records, and Hugging Face model cards. No blog posts
or secondary write-ups were used for licence claims.

## Bottom line

There is no unambiguously free, commercially clean, high-accuracy model that
turns an arbitrary real-world chessboard photo into a correct FEN out of the box.

- The most accurate published real-photo system found, ChessQueries
  (99.5% exact-board on ChessReD), is **Noncommercial only** for both code and weights.
- The commercially cleanest complete pipeline is the oldest one, **chesscog**
  (MIT code and weights, CC BY 4.0 synthetic training data), but it was trained
  on synthetic renders and needs its few-shot fine-tuning step for a new real chess set.
- The commercially cleanest modern component is **cstr/chess-board-photo-onnx**
  (MIT model card), but it is only the two per-square classifiers. It still needs
  a board localiser, and its stated accuracy drops sharply on an unseen chess set.
- Everything YOLO-based inherits Ultralytics AGPL-3.0 conditions regardless of
  what the individual model card claims. See section 5.
- Do not train a commercial model on ChessReD or SLCC: both are NonCommercial
  datasets (sections 1 and 4.1).

Accuracy terms used below, never conflated: **exact-board** means the whole
64-square position (and therefore the board part of the FEN) is correct.
**Per-square / per-piece** means individual squares or pieces correct; a 99%
per-square model still gets roughly half of all boards wrong.

## Summary table

| Candidate | Licence as stated at source | Weights downloadable | Training data | Reported accuracy (as stated) | Commercial verdict |
|---|---|---|---|---|---|
| tmasouris/end-to-end-chess-recognition | Code: "MIT License". Dataset: "CC BY-NC-SA 4.0" | Yes, Google Drive link in README; no GitHub release | Real smartphone photos (ChessReD) | 15.26% exact-board | Code yes; weights risky - trained on NonCommercial ShareAlike data |
| georg-wolflein/chesscog | Code: "MIT License". Dataset: "CC-By Attribution 4.0 International" | Yes, GitHub release 0.1.0 via download scripts | Synthetic Blender renders (~5,000) | 93.86% exact-board (synthetic test); 0.23% per-square error | Yes, cleanest complete option; expect fine-tuning per chess set |
| davidmallasen/LiveChess2FEN | "GNU AFFERO GENERAL PUBLIC LICENSE Version 3" | Yes, many files in release v0.1.0 | Real piece photos (release dataset) | 92% per-piece classification; 95% board detection; no exact-board figure | Only if the whole product is AGPL-3.0; no for a proprietary app |
| joelseytre/chessqueries + chessq-lite (HF) | "PolyForm Noncommercial License 1.0.0" (code and weights) | Yes, safetensors on HF | Real + synthetic + broadcast frames (joint) | 99.5% / 98.5% / 87.1% exact-board (ChessReD / ChessCog / SLCC) | No - commercial use expressly not licensed |
| cstr/chess-board-photo-onnx (HF) | Model card: "mit" | Yes, 2 ONNX files on HF | Mixed: synthetic CC BY 4.0 + real MIT + Roboflow CC BY 4.0 | 99.6-99.9% per-square (seen sets); 85% per-square (unseen set) | Yes per card, but classifiers only - not a standalone photo-to-FEN model |
| KanisornPutta/chess-model-yolov8m (HF) | Card YAML: "mit", but card text says follow original repo / contact author for commercial use | Yes, .pt on HF | "custom-chess-dataset", original author siromermer | None stated on card | No - conflicting licence, original repo has no LICENSE, plus Ultralytics AGPL |
| Mohammadjalkhatib/chess_yolo (HF) | No licence in card metadata; "license: mit" appears in a trailing dataset block | Yes, yolov8x_chess.pt | "Custom dataset of top-view chessboard images" | None numeric; "performs accurately in controlled environments" | Not reliably - top-down only, no metrics, plus Ultralytics AGPL |
| dopaul/chessboard-detector (HF) | No licence stated on card | Yes, best.pt | "chess piece datasets", unspecified | None stated | No - no licence grant, plus Ultralytics AGPL |
| honi05/ChessBoardDetector (HF) | Card: "mit" | Yes, 2 .pt files (YOLOv11) | Not stated on card | None stated on card | Not reliably - MIT claim conflicts with Ultralytics AGPL; linked GitHub repo not publicly reachable at research time |
| harshitpawar64/chessvision (HF) | Card: "mit" | Yes, .pt + .onnx classifier | Not stated (card is empty apart from licence) | None stated | Not evaluable - no documentation, data, or metrics |
| VXInteractive/BoardCNN (HF) | YAML: "lgpl-3.0"; card body: "License: GNU GPL v3" | Yes, board374k.pth | 5k generated Lichess-style images (2D, synthetic) | None stated | No for real photos - card says pre-trained models are "not made for scanning 3D boards"; licence is also internally inconsistent |

## 1. tmasouris/end-to-end-chess-recognition (ChessReD, VISAPP 2024)

- Repo: https://github.com/tmasouris/end-to-end-chess-recognition
- Code licence: the repo `LICENSE` file is the "MIT License"
  (Copyright (c) 2026 Athanasios Masouris):
  https://raw.githubusercontent.com/tmasouris/end-to-end-chess-recognition/main/LICENSE
- Pretrained weights: yes. The README says "you can download our pretrained model"
  with a Google Drive link, and separately links pre-processed 1024x1024 training
  images, also on Google Drive. There is no GitHub release (releases list is empty).
  The weights have no separate licence statement of their own:
  https://raw.githubusercontent.com/tmasouris/end-to-end-chess-recognition/main/README.md
- Dataset licence (decisive): the official 4TU.ResearchData record for ChessReD
  states Licence: "CC BY-NC-SA 4.0". NC = NonCommercial, SA = ShareAlike:
  https://data.4tu.nl/datasets/99b5c721-280b-450b-b058-b2900b69a90f
- Training data: real photos. README and paper: 10,800 images from 100 games,
  "captured using various smartphone cameras" / "real photographs":
  https://arxiv.org/abs/2310.04086
- Accuracy: **15.26% exact-board** ("board recognition accuracy of 15.26%",
  "successfully recognizing the chess pieces' configuration in 15.26% of
  ChessReD's test images"). This is exact-board, not per-piece:
  https://arxiv.org/abs/2310.04086
- Commercial verdict: the MIT code may be used commercially, but the released
  checkpoint was trained solely on CC BY-NC-SA 4.0 data. Using that checkpoint,
  or retraining on ChessReD, in a commercial product conflicts with the dataset's
  NonCommercial term, and ShareAlike adds redistribution obligations. Treat the
  weights as not commercially clean. The accuracy is in any case too low to ship
  (about 1 board in 7 fully correct).

## 2. georg-wolflein/chesscog

- Repo: https://github.com/georg-wolflein/chesscog (paper: Wölflein and
  Arandjelović, Journal of Imaging 2021, https://doi.org/10.3390/jimaging7060094)
- Code licence: repo `LICENSE` is the "MIT License" (Copyright (c) 2021 Georg Wölflein):
  https://raw.githubusercontent.com/georg-wolflein/chesscog/master/LICENSE
- Pretrained models: yes. README instructs running
  `python -m chesscog.occupancy_classifier.download_model` and
  `python -m chesscog.piece_classifier.download_model`; both scripts download
  zips from GitHub release 0.1.0 in the same MIT repo:
  https://raw.githubusercontent.com/georg-wolflein/chesscog/master/chesscog/piece_classifier/download_model.py
- Training data: **synthetic, not real**. README: "trained using a dataset of
  ~5,000 synthetically generated images of chess positions (3D renderings...)".
  The OSF dataset record "Dataset of Rendered Chess Game State Images" says
  4,888 synthetic Blender images, and its OSF licence record is
  "CC-By Attribution 4.0 International" (commercial use allowed with attribution):
  https://doi.org/10.17605/OSF.IO/XF3KA and OSF API licence record
  https://api.osf.io/v2/licenses/563c1cf88c5e4a3877f9e96a/
  Real-photo use is via the paper's few-shot transfer learning (fine-tune from
  two photos of a new set), not the base weights alone.
- Accuracy (from the paper, as quoted in the ChessReD paper's comparison):
  **93.86% exact-board** on its synthetic test set with a **0.23% per-square
  error rate**; after transfer learning, **88.89% exact-board** and 0.17%
  per-square error on previously unseen real chess-set photos:
  https://arxiv.org/abs/2310.04086 (section comparing to Chesscog) and
  https://arxiv.org/abs/2104.14963
- Commercial verdict: **Yes - the cleanest complete photo-to-FEN option.**
  MIT code and weights plus CC BY 4.0 training data impose only notice and
  attribution duties. Caveats are technical, not legal: synthetic training
  domain, 2021-era pipeline (corner/line board localisation plus two
  classifiers), and per-set fine-tuning should be expected for reliable
  real-photo accuracy.

## 3. davidmallasen/LiveChess2FEN

- Repo: https://github.com/davidmallasen/LiveChess2FEN
  (paper: https://arxiv.org/abs/2012.06858)
- Licence: repo `LICENSE` is the "GNU AFFERO GENERAL PUBLIC LICENSE Version 3";
  README repeats AGPL-3.0 with a tldrlegal summary link:
  https://raw.githubusercontent.com/davidmallasen/LiveChess2FEN/master/LICENSE
- Model files: yes, extensively. Release v0.1.0 "Initial release" contains
  AlexNet, DenseNet201, MobileNetV2 variants, NASNetMobile, SqueezeNet and
  Xception weights in .h5, .onnx and .trt formats, plus ChessPiecesDataset.zip
  and TestImages.zip. README usage step 1: download the .h5/.onnx/.trt models
  from releases into `data/models`:
  https://github.com/davidmallasen/LiveChess2FEN/releases/tag/v0.1.0
- Training data: real photos. The release ships a ChessPiecesDataset and the
  paper describes training/testing with different real chess sets; the pipeline
  targets live camera / Jetson Nano input rather than renders:
  https://arxiv.org/abs/2012.06858
- Accuracy: paper abstract states the framework digitises a position in under
  1 second "with 92% accuracy when classifying the pieces and 95% when detecting
  the board". These are **per-piece classification** and **board detection**
  figures. No exact-board / exact-FEN accuracy is claimed - do not read 92% as
  whole-board accuracy:
  https://arxiv.org/abs/2012.06858
- Commercial verdict: **Only inside an AGPL-3.0 product.** AGPL-3.0 permits
  commercial use only if the complete corresponding source, including code that
  uses it over a network, is offered under AGPL-3.0. The authors offer no
  separate commercial licence in the repo. It is therefore not usable in a
  closed-source commercial app.

## 4. Hugging Face models

### 4.1 ChessQueries - joelseytre/chessqueries and joelseytre/chessq-lite (strongest, but Noncommercial)

- Model cards: https://huggingface.co/joelseytre/chessqueries and
  https://huggingface.co/joelseytre/chessq-lite
- Licence as stated on both cards: `license: other`,
  `license_name: polyform-noncommercial-license-1.0.0`, with card text:
  "The ChessQueries model weights are licensed under the PolyForm Noncommercial
  License 1.0.0... commercial use requires separate permission."
  The code repo states the same for code and adds "Commercial use is not licensed":
  https://raw.githubusercontent.com/JSeytre/chessqueries/main/README.md
- Weights: yes, downloadable safetensors (ViT-L 743 MB, ViT-B, ViT-S/Lite 63 MB)
  plus Core ML exports for Lite:
  https://huggingface.co/joelseytre/chessqueries/raw/main/README.md
- Training data: real plus synthetic plus broadcast. Card: "jointly trained on
  ChessReD, ChessCog, and SLCC". ChessReD is real smartphone photos (section 1),
  ChessCog is synthetic renders (section 2), SLCC is annotations of broadcast
  tournament frames. Note the compounding NonCommercial terms: ChessReD is
  CC BY-NC-SA 4.0 and the SLCC annotations dataset card states
  `license: cc-by-nc-4.0`, with source broadcasts not redistributed:
  https://huggingface.co/datasets/joelseytre/slcc/raw/main/README.md
- Accuracy: repo README table headed "Best exact-board accuracy": ChessReD
  **99.5%**, ChessCog **98.5%**, SLCC **87.1%**, CVChess zero-shot 87.6%.
  The paper abstract phrases the ChessReD result as improving "from 15.3% to
  99.2%" with "0.01 wrong squares per board" (the small difference between
  99.2% and 99.5% is between paper and repo table; both are exact-board):
  https://arxiv.org/abs/2608.30762
- Commercial verdict: **No.** This is technically the best real-photo model
  found and the only one claiming near-solved exact-board accuracy, but
  PolyForm Noncommercial bars commercial use of code and weights without a
  separate paid permission from the author (card gives contact@chessq.org).

### 4.2 cstr/chess-board-photo-onnx (commercially usable component)

- Model card: https://huggingface.co/cstr/chess-board-photo-onnx
- Licence as stated: card front-matter `license: mit`. Two ONNX files
  (board_photo_occupancy.onnx, board_photo_pieces.onnx), MobileNetV3-Small
  classifiers initialised from torchvision ImageNet weights.
- Training data as stated on the card: chesscog synthetic renders
  (CC BY 4.0), samryan18/chess-dataset (card states MIT), and Roboflow 100
  "chess pieces" (CC BY 4.0) - a mix of synthetic and real:
  https://huggingface.co/cstr/chess-board-photo-onnx/raw/main/README.md
- Accuracy as stated on the card (per-square, end-to-end with the chesscog
  localiser): "99.6-99.9% of squares on held-out photos of the piece sets seen
  in training; 85% of squares... on chesscog's photos of an unseen wooden set."
  No exact-board figure is claimed. At 85% per-square on an unseen set, most
  boards will contain at least one wrong square.
- Commercial verdict: **Yes per the card (MIT), with two limits.** (1) It is
  not a complete photo-to-FEN model: it consumes square/piece crops produced by
  a chesscog-style board localiser, which must be supplied separately (chesscog
  itself is MIT, section 2). (2) Generalisation to unseen chess sets is the
  weak point, per its own numbers. It is a legitimate commercial starting
  component, not a drop-in solution.

### 4.3 Other HF candidates checked and rejected

- VXInteractive/BoardCNN: https://huggingface.co/VXInteractive/BoardCNN -
  YAML licence "lgpl-3.0" but card body says "License: GNU GPL v3" (inconsistent).
  Trained on "5k generated images... from lichess" (2D synthetic diagrams, not
  photos); card Out-of-Scope: "The pre-trained models are not made for scanning
  3D boards." Not a real-photo model.
- harshitpawar64/chessvision: https://huggingface.co/harshitpawar64/chessvision -
  `license: mit`, ships chess_piece_classifier .pt/.onnx, but the card contains
  nothing beyond the licence line: no training data, task definition, or accuracy.
  Not evaluable as a photo-to-FEN model.
- PRANAYugale/chess-board-state-extractor and abdullahq19/chessboard-digitizer:
  MIT-tagged cards with no substantive card content (the latter ships a .tflite
  file). No data or accuracy statements to rely on:
  https://huggingface.co/api/models/PRANAYugale/chess-board-state-extractor and
  https://huggingface.co/api/models/abdullahq19/chessboard-digitizer

## 5. Ultralytics YOLO-based chess models and the AGPL problem

Primary licensing sources:

- The Ultralytics repo `LICENSE` is the "GNU AFFERO GENERAL PUBLIC LICENSE
  Version 3": https://raw.githubusercontent.com/ultralytics/ultralytics/main/LICENSE
- Ultralytics' own licensing page states the free AGPL-3.0 option applies if
  you are "comfortable open-sourcing your entire project under AGPL-3.0"
  (academic, personal, fully-disclosed open-source use), and positions an
  Ultralytics Enterprise License for commercial deployment in "SaaS, embedded,
  and customer-facing products": https://www.ultralytics.com/license

Implication: any chess model distributed as Ultralytics YOLO weights (.pt) and
run through the Ultralytics library is not made commercially free by the model
card saying "MIT". For a proprietary commercial product you must either release
the whole product under AGPL-3.0 or buy an Ultralytics Enterprise licence.
The chess-specific cards additionally fail on their own terms:

- KanisornPutta/chess-model-yolov8m:
  https://huggingface.co/KanisornPutta/chess-model-yolov8m - card YAML claims
  `license: mit` and ships chess-model-yolov8m.pt (12 piece classes, detection
  only - FEN assembly is left to the user, input is expected to be a warped
  board image). But the card's own License section says: "Follow the license
  terms defined in the original repository. If none were specified, please
  contact the original author before using the model commercially." The original
  repo, siromermer/Dynamic-Chess-Board-Piece-Extraction, has no LICENSE file
  (no licence = no permission granted):
  https://github.com/siromermer/Dynamic-Chess-Board-Piece-Extraction
  No accuracy figures are stated on the card. Verdict: do not use commercially.
- Mohammadjalkhatib/chess_yolo:
  https://huggingface.co/Mohammadjalkhatib/chess_yolo - ships yolov8x_chess.pt,
  trained on a "Custom dataset of top-view chessboard images" (real, but
  top-down only). Card metadata carries no licence; a trailing block in the card
  contains "license: mit". Performance section gives no numbers ("performs
  accurately in controlled environments", "achieved great results"). Verdict:
  not a general photo-to-FEN model and not commercially reliable.
- dopaul/chessboard-detector:
  https://huggingface.co/dopaul/chessboard-detector - ships best.pt (YOLOv8/YOLOv11),
  "trained on chess piece datasets" (unspecified, no split between real and
  synthetic), no licence stated anywhere on the card, no accuracy stated.
  Verdict: no licence grant at all, plus AGPL framework. Do not use.
- honi05/ChessBoardDetector:
  https://huggingface.co/honi05/ChessBoardDetector - card states
  `license: mit` and describes a genuinely complete pipeline ("Two-model YOLOv11
  pipeline that converts a chessboard photograph into a FEN string") with
  board_detector.pt and piece_detector.pt. However the card states no training
  data and no accuracy, the linked GitHub source repo was not publicly reachable
  when checked, and YOLOv11/Ultralytics AGPL applies regardless of the card's
  MIT tag. Verdict: not commercially reliable as published.

## 6. What this means for building a commercial photo-to-FEN feature

1. **Do not build on** ChessQueries weights (PolyForm Noncommercial),
   LiveChess2FEN (AGPL-3.0), any Ultralytics YOLO chess weights (AGPL-3.0
   framework plus unreliable card licences), or models with no licence
   (dopaul, siromermer-derived KanisornPutta upload).
2. **Do not train on** ChessReD (CC BY-NC-SA 4.0) or SLCC annotations
   (CC BY-NC 4.0) for a commercial product. This also taints the released
   ChessReD checkpoint in section 1 despite its MIT code.
3. **Permitted starting points:** chesscog (MIT code/weights, CC BY 4.0
   synthetic data) as a complete but dated pipeline, and/or the MIT
   cstr/chess-board-photo-onnx classifiers with a chesscog-style localiser.
   Budget for collecting your own real photos of target chess sets and
   fine-tuning: every source above shows unseen-set accuracy, not headline
   accuracy, is the binding constraint (chesscog 88.89% exact-board after
   two-photo fine-tuning; cstr 85% per-square on an unseen set).
4. **Report accuracy honestly:** require exact-board (exact-FEN) numbers on
   held-out photos of unseen chess sets before shipping. Per-piece figures
   such as LiveChess2FEN's 92% and per-square figures such as cstr's 99.6%
   (seen sets) do not mean 92-99% of photos produce a correct FEN.
