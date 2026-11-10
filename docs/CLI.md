# Comic command-line interface

The app build embeds `Me2Press.app/Contents/MacOS/me2press-cli`. Build/archive the Me2Press scheme to include it. GUI and CLI share the comic conversion workers.

```sh
me2press-cli --version
me2press-cli settings
me2press-cli comic --request request.json
```

The settings command prints a read-only snapshot of the app's KindleGen path, concurrency, author and reading direction. Pass the snapshot back to keep a batch reproducible.

```json
{
  "settings": {
    "kindlegenPath": "/path/to/kindlegen",
    "maxConcurrency": 2,
    "authorName": "Author",
    "readingDirection": "rtl"
  },
  "jobs": [
    {
      "id": "B001",
      "input": "/path/to/Book_Vol.01",
      "output": "/path/to/work/mobi/B001",
      "readingDirection": "rtl"
    }
  ]
}
```

Each input is one image directory. Its name becomes the book title; the first image is the cover. Per-job readingDirection is optional and overrides the snapshot (rtl or ltr). Use unique IDs and input directories. Output directories are created as needed; use dedicated working directories because retries replace matching MOBI files there.

Standard output uses newline-delimited JSON: `job_started`, `job_result`, and a final `summary` with `results` in request order. Job results contain `id`, `status` (`succeeded`, `failed`, `cancelled`), `outputs`, and an optional `error`. Request/startup errors use an `error` event. Detailed diagnostics go to standard error.

Exit codes: 0 = all jobs succeeded; 1 = processing failed; 2 = invalid request/settings; 130 = cancelled. SIGINT/SIGTERM cancel owned child processes and finish the result report. Saved app preferences are read without modification; no windows are opened.

Additional events: `progress` contains an id and real stage, without simulated percentages. Results also include `warnings`; KindleGen exit code 1 remains success with warnings. The outputs list is authoritative and includes automatically split volumes.

Set ME2PRESS_TEST_KINDLEGEN when running conversion tests against a locally installed KindleGen.
