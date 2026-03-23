import { useState } from "react";

import { materializeDataTemplateFolder, openPath } from "../../lib/api";
import type {
  DataTemplateFolderResponse,
  DataTemplateVariant,
} from "../../lib/types";
import { getErrorMessage } from "../../lib/workbench";
import {
  formatTemplateBuildError,
  formatTemplateOpenError,
  validateTemplateFolderResponse,
} from "./helpers";

type Args = {
  exportOutputDir: string | null | undefined;
  setGlobalError(error: string | null): void;
};

export function useWizardActions({
  exportOutputDir,
  setGlobalError,
}: Args) {
  const [templateFolderBusy, setTemplateFolderBusy] = useState(false);
  const [templateBuildError, setTemplateBuildError] = useState<string | null>(null);
  const [templateOpenError, setTemplateOpenError] = useState<string | null>(null);
  const [latestTemplateFolder, setLatestTemplateFolder] = useState<DataTemplateFolderResponse | null>(
    null,
  );

  const openTemplateFolder = async (variant: DataTemplateVariant) => {
    setTemplateBuildError(null);
    setTemplateOpenError(null);
    setLatestTemplateFolder(null);
    setTemplateFolderBusy(true);
    try {
      const response = await materializeDataTemplateFolder({ variant });
      validateTemplateFolderResponse(response);
      setLatestTemplateFolder(response);
      try {
        await openPath(response.folder_path);
      } catch (error) {
        setTemplateOpenError(formatTemplateOpenError(error));
      }
    } catch (error) {
      setTemplateBuildError(formatTemplateBuildError(error));
    } finally {
      setTemplateFolderBusy(false);
    }
  };

  const reopenTemplateFolder = async () => {
    if (!latestTemplateFolder) {
      return;
    }
    setTemplateOpenError(null);
    try {
      await openPath(latestTemplateFolder.folder_path);
    } catch (error) {
      setTemplateOpenError(formatTemplateOpenError(error));
    }
  };

  const openOutputFolder = async () => {
    if (!exportOutputDir) {
      return;
    }
    setGlobalError(null);
    try {
      await openPath(exportOutputDir);
    } catch (error) {
      setGlobalError(getErrorMessage(error));
    }
  };

  return {
    templateFolderBusy,
    templateBuildError,
    templateOpenError,
    latestTemplateFolder,
    openTemplateFolder,
    reopenTemplateFolder,
    openOutputFolder,
  };
}
