import type { Release, ReleaseInput, Session } from "./types";

export class ApiError extends Error {
  status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(path, {
    credentials: "include",
    ...init,
    headers: {
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...init.headers,
    },
  });
  if (response.status === 204) {
    return undefined as T;
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const detail =
      typeof data === "object" && data !== null && "detail" in data
        ? String((data as { detail: unknown }).detail)
        : "Anfrage fehlgeschlagen";
    throw new ApiError(detail, response.status);
  }
  return data as T;
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) {
    return error.message;
  }
  if (error instanceof Error) {
    return error.message;
  }
  return "Unbekannter Fehler";
}

export function listReleases(): Promise<Release[]> {
  return request<Release[]>("/api/releases");
}

export function getRelease(slug: string): Promise<Release> {
  return request<Release>(`/api/releases/${encodeURIComponent(slug)}`);
}

export function getSession(): Promise<Session> {
  return request<Session>("/api/session");
}

export function login(username: string, password: string): Promise<Session> {
  return request<Session>("/api/login", {
    method: "POST",
    body: JSON.stringify({ username, password }),
  });
}

export function logout(): Promise<Session> {
  return request<Session>("/api/logout", { method: "POST" });
}

export function listAdminReleases(): Promise<Release[]> {
  return request<Release[]>("/api/admin/releases");
}

export function createRelease(input: ReleaseInput): Promise<Release> {
  return request<Release>("/api/admin/releases", {
    method: "POST",
    body: JSON.stringify(input),
  });
}

export function updateRelease(id: number, input: ReleaseInput): Promise<Release> {
  return request<Release>(`/api/admin/releases/${id}`, {
    method: "PUT",
    body: JSON.stringify(input),
  });
}

export function deleteRelease(id: number): Promise<void> {
  return request<void>(`/api/admin/releases/${id}`, { method: "DELETE" });
}
