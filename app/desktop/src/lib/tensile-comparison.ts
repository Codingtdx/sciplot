import type {
  TensileComparisonSource,
  TensileReplicateResponse,
  TensileWorkbookSummary,
} from "./types";

function formatLeaf(path: string) {
  return path.split(/[/\\]/).pop() ?? path;
}

export function inferTensileWorkbookLabel(workbookPath: string) {
  const leaf = formatLeaf(workbookPath);
  const stem = leaf.replace(/\.[^.]+$/, "").trim();
  return stem || leaf || "Tensile Workbook";
}

function dedupeLabels(labels: string[]) {
  const counts = new Map<string, number>();
  return labels.map((label) => {
    const next = (counts.get(label) ?? 0) + 1;
    counts.set(label, next);
    return next === 1 ? label : `${label} (${next})`;
  });
}

export function normalizeTensileComparisonSources(sources: TensileComparisonSource[]) {
  const baseLabels = sources.map((source) => inferTensileWorkbookLabel(source.workbook_path));
  const deduped = dedupeLabels(baseLabels);
  return sources.map((source, index) => ({
    ...source,
    label: deduped[index],
  }));
}

export function upsertTensileComparisonSource(
  sources: TensileComparisonSource[],
  source: TensileComparisonSource,
) {
  const index = sources.findIndex((item) => item.workbook_path === source.workbook_path);
  const next =
    index === -1
      ? [...sources, source]
      : sources.map((item, currentIndex) => (currentIndex === index ? source : item));
  return normalizeTensileComparisonSources(next);
}

export function moveTensileComparisonSource(
  sources: TensileComparisonSource[],
  workbookPath: string,
  offset: -1 | 1,
) {
  const index = sources.findIndex((item) => item.workbook_path === workbookPath);
  if (index === -1) {
    return normalizeTensileComparisonSources(sources);
  }
  const targetIndex = index + offset;
  if (targetIndex < 0 || targetIndex >= sources.length) {
    return normalizeTensileComparisonSources(sources);
  }
  const next = [...sources];
  const [item] = next.splice(index, 1);
  next.splice(targetIndex, 0, item);
  return normalizeTensileComparisonSources(next);
}

export function tensileComparisonSourceFromPreprocess(
  result: TensileReplicateResponse,
): TensileComparisonSource {
  return normalizeTensileComparisonSources([
    {
      workbook_path: result.output_path,
      label: inferTensileWorkbookLabel(result.output_path),
      sheet_names: result.sheet_names,
      sample_count: result.sample_count,
      representative_filename: result.representative_filename,
      metrics: result.metrics,
    },
  ])[0];
}

export function tensileComparisonSourceFromSummary(
  summary: TensileWorkbookSummary,
): TensileComparisonSource {
  return normalizeTensileComparisonSources([
    {
      ...summary,
      label: inferTensileWorkbookLabel(summary.workbook_path),
    },
  ])[0];
}
