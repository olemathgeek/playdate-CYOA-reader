# Story Paths (playdate-CYOA-reader)

An easy-reader choose-your-own-adventure for the Playdate, made for early readers.
Big text, short sentences, and simple choices.

## Controls
- **Main menu**: pick a story from the list, or "Keep reading" to go back to the last page you were on
- **Down / crank**: read more of the page, then highlight a choice
- **Up / Down**: move between choices
- **A**: pick the highlighted choice
- **B**: go back one page
- **Menu button**: "title screen" or "start over"

Your spot (story, page and B-back history) is saved with `playdate.datastore` on every page
and when the Playdate sleeps or quits. Reaching an ending clears the save.

## Stories
Each story is one JSON file in `source/stories/`. Any `.json` file there shows up in the
main menu, sorted by title. Example: `source/stories/pip-and-the-red-ball.json`.

```json
{
    "title": "Pip and the Red Ball",
    "start": "start",
    "pages": {
        "start": {
            "text": "Pip is a little dog. ...",
            "choices": [
                { "label": "Look in the park.", "to": "park" },
                { "label": "Look by the pond.", "to": "pond" }
            ]
        },
        "hill": {
            "text": "... The End.",
            "ending": true
        }
    }
}
```

- `title`: name shown in the menu
- `start`: id of the first page (defaults to `"start"`)
- `pages`: object keyed by page id. Each page has `text`, plus either `choices`
  (each `{ "label", "to" }` where `to` is another page id) or `"ending": true`.
- Ending pages get "Read again!" and "Pick a new story" buttons automatically.
- A story with a broken `to` link or missing `text` is skipped, and the reason is printed to the Simulator console.
- Use plain quotes and apostrophes, not curly ones. Escape quotes inside text as `\"`.

## Build
```bash
pdc source builds/StoryPaths.pdx
```
Or use the VS Code task "Playdate: Build and Run" (same setup as the other Playdate projects).
