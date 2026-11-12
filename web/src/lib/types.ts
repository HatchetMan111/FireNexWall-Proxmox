export type ReleaseStatus = "stable" | "rc" | "beta" | "alpha" | "security";

export interface DownloadLink {
  label: string;
  url: string;
  platform?: string | null;
  sha256?: string | null;
}

export interface Release {
  id: number;
  version: string;
  slug: string;
  title: string;
  status: ReleaseStatus;
  release_date: string;
  summary: string;
  body_md: string;
  known_issues_md: string;
  downloads: DownloadLink[];
  published: boolean;
  created_at: string;
  updated_at: string;
}

export interface ReleaseInput {
  version: string;
  slug?: string;
  title: string;
  status: ReleaseStatus;
  release_date: string;
  summary: string;
  body_md: string;
  known_issues_md: string;
  downloads: DownloadLink[];
  published: boolean;
}

export interface Session {
  authenticated: boolean;
  username: string | null;
}
