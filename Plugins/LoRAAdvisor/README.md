# LoRA Advisor

A plug-in for DT Hub with two things in one tab: a **visual list of your LoRAs**, each with a thumbnail and notes, and the **advice of the local LLM** on which ones suit what you want to generate. **Works with: all model families.** Needs DT Hub 0.2.2 or later.

The list matters more than the advice: it works without a language model.

## Your LoRAs (left)

Every LoRA of the server, grouped by family, the family of the current model first. A row shows the thumbnail, the name, the trigger word and weight (those of the app's LoRA manager, read-only here) and the first line of the notes. Click a family's name to open or close it: all are closed at first except the current model's, which opens again whenever the model changes, and a search in the filter shows its results in every family. Click a row to open it: the **Notes** (one free text field) and the **link** of the LoRA's page; its thumbnail appears large on the card at the top right, with the **Thumbnail** menu (a file, the Control tab's start image, or none). Click its name to close it. You can also **drop a picture on a row** to make it its thumbnail: a file from the Finder, or a picture dragged from a browser when the browser hands over the picture itself (an address alone is not followed).

**Add** puts the LoRA on the Generation tab with its weight and trigger word. It is off for a LoRA of another family (LoRAs of different families cannot be mixed); a LoRA that is on the tab already says so.

Three steps fill the list in, each with its own button and **never by themselves**:

1. **Find pages** looks on Civitai and on Hugging Face, by name, for the page of each LoRA that has none. The words that only say which model a LoRA is for are set aside, whether a tag of your own (`k2`, `q21`, `zit`) or the author's (`[KREA 2]`), and the search is made by the name alone first, and only if that brings nothing is it repeated with the usual wording for that family in front ("Krea 2 Detail Slider"; those words in front can drown the name). Results made for another model are left out, and so are those that share no word with the name (a LoRA for Krea 2 never gets a page for SD 1.5; when a page holds versions for several models, the link goes to the version for yours; a base model the plug-in does not know is kept). A result is taken at once only when its name is the LoRA's (capitals, punctuation and a version at the end such as `v1.0` do not count): those rows say *found automatically* and have **Not this one**. Otherwise the row says *choose the page* and, opened, lists up to five candidates (three from Civitai, two from Hugging Face, the most downloaded first) with **Use This** and a button that opens the page in your browser. With no result at all it says *page not found*. **Search again** repeats the search for one LoRA.
2. **Import** brings the text of the page into the notes and the first picture of its gallery as the thumbnail. It runs after a page is found, or from **Import from the page** with a link you paste: a model page of Civitai (`civitai.com` or `civitai.red`, with `?modelVersionId=` for a LoRA that is one version of a bundle) or a repository of Hugging Face.
3. **Summarise all** has the local LLM rewrite the notes that are still the raw beginning of a page as a short summary (what the LoRA is for, its trigger words, the suggested weights).

Each step works only on what is missing: the first time on everything, afterwards on the new LoRAs and on those whose link you gave or changed. Notes you wrote or corrected yourself are never touched by a later step (an import asks before replacing them), and neither is a thumbnail you chose from a file or from the Control tab's start image.

## Advise (right)

A text field that starts as the current prompt; leave it to get advice for the prompt, or write what you are after ("80s film look"). **Advise** has the LLM pick up to five LoRAs among those of the **current model's family**, each with a weight you can change and one sentence of explanation. **Add** (or **Update the weight** for a LoRA already on the tab) sends it to the Generation tab; **Add all** sends them all. The model sees the name, the trigger word and the first 300 characters of the notes of each LoRA, so better notes give better advice. It needs a language model assigned to plug-ins (Settings › LLM).

## Network

This is the one plug-in of DT Hub that uses the network, and only when you press **Find pages**, **Search again** or **Import from the page**:

- **Find pages** sends the **names of your LoRAs** to Civitai and to Hugging Face as search text (up to three requests per LoRA).
- **Import** asks Civitai's public API or Hugging Face for the page, and downloads its first picture.
- Nothing else leaves your Mac: no prompt, no image, no account. The summaries and the advice are written by the local LLM.

Requests are `GET` over https, with no cookies and no credentials, to `civitai.com`, `huggingface.co` and their own servers only; a redirect anywhere else is refused, and so are answers beyond 5 MB (text) or 10 MB (a picture). A downloaded picture is decoded and written again as a 256-pixel JPEG. The text of a page is treated as data: it is shown as plain text, and the LLM is told to summarise it and ignore any instruction it contains.

## Good to know

- The plug-in must be **on for the job** (header menu) to see the LoRAs and to add them.
- The notes and thumbnails are **global**, not per project: `~/Library/Application Support/DT Hub/Data/LoRAAdvisor/` (`loras.json`, `thumbs/`, `pages/`). The entries of LoRAs the server no longer has are kept.
- The search is by name and can find nothing: a LoRA you renamed, one that is not on either site, one that is a version of a bundle. Paste the link for those. Look at a candidate's page before you take it: on Hugging Face a LoRA often has several copies.
- Pages that need an account are not read; write the notes and choose a picture yourself.
- The first picture of a page's gallery is taken as it is, whatever it shows.

## Build

    Plugins/LoRAAdvisor/Scripts/build.sh OUT_FOLDER

Tests: `cd Plugins/LoRAAdvisor && swift test` (no test touches the network or a language model; `LA_RENDER_DIR=folder swift test --filter RenderTests` writes pictures of the tab). Design: `docs/superpowers/specs/2026-10-13-plugin-lora-advisor-design.md`.
