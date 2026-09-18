import { HttpClient } from '@angular/common/http';
import { Injectable } from '@angular/core';
import { Observable } from 'rxjs';

export interface ApiResponse<T> {
  success: boolean;
  datas?: T;
}

export interface UserRole {
  id: number;
  name?: string;
}

export interface CurrentUser {
  id: number;
  username?: string;
  email?: string;
  rolesId?: number;
  roles?: UserRole;
}

type AdminPayload = Record<string, unknown> | FormData;

@Injectable({
  providedIn: 'root'
})
export class AppService {
  private readonly apiUrl = 'http://localhost:3000/api';
  private readonly publicUrl = 'http://localhost:3000';
  private readonly currentUserKey = 'library_admin_user';

  constructor(private http: HttpClient) {}

  login(login: string, password: string): Observable<ApiResponse<CurrentUser>> {
    return this.http.post<ApiResponse<CurrentUser>>(`${this.apiUrl}/users/login`, { login, password });
  }

  fileUrl(fileName: string): string {
    if (/^(https?:|blob:|data:)/.test(fileName)) {
      return fileName;
    }

    return `${this.publicUrl}/${encodeURIComponent(fileName)}`;
  }

  setCurrentUser(user: CurrentUser): void {
    localStorage.setItem(this.currentUserKey, JSON.stringify(user));
  }

  getCurrentUser(): CurrentUser | null {
    const rawUser = localStorage.getItem(this.currentUserKey);
    if (!rawUser) {
      return null;
    }

    try {
      return JSON.parse(rawUser) as CurrentUser;
    } catch {
      localStorage.removeItem(this.currentUserKey);
      return null;
    }
  }

  logout(): void {
    localStorage.removeItem(this.currentUserKey);
  }

  isLoggedIn(): boolean {
    return this.getCurrentUser() !== null;
  }

  isAdmin(user: CurrentUser | null = this.getCurrentUser()): boolean {
    if (!user) {
      return false;
    }

    const roleName = (user.roles?.name || '').toLowerCase();
    return user.rolesId === 1 || roleName.includes('admin') || roleName.includes('administrator');
  }

  list<T>(endpoint: string): Observable<ApiResponse<T[]>> {
    return this.http.get<ApiResponse<T[]>>(`${this.apiUrl}/${endpoint}`);
  }

  create<T>(endpoint: string, payload: AdminPayload): Observable<ApiResponse<T>> {
    return this.http.post<ApiResponse<T>>(`${this.apiUrl}/${endpoint}`, payload);
  }

  update<T>(endpoint: string, payload: AdminPayload): Observable<ApiResponse<T>> {
    return this.http.put<ApiResponse<T>>(`${this.apiUrl}/${endpoint}`, payload);
  }

  updateBookVisibility(id: number, showInApp: boolean): Observable<ApiResponse<{ id: number; show_in_app: boolean }>> {
    return this.http.put<ApiResponse<{ id: number; show_in_app: boolean }>>(
      `${this.apiUrl}/books/${id}/show_in_app`,
      { show_in_app: showInApp }
    );
  }

  delete(endpoint: string, id: number): Observable<ApiResponse<unknown>> {
    return this.http.delete<ApiResponse<unknown>>(`${this.apiUrl}/${endpoint}/${id}`);
  }
}
