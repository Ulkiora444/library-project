import { Component } from '@angular/core';
import { Router } from '@angular/router';
import { AppService } from '../app.service';

type Language = 'ru' | 'tm' | 'en';
type ThemeName = 'dark' | 'light' | 'amber';
type LoginTranslationKey =
  | 'admin'
  | 'welcome'
  | 'subtitle'
  | 'login'
  | 'loginPlaceholder'
  | 'password'
  | 'passwordPlaceholder'
  | 'button'
  | 'checking'
  | 'language'
  | 'theme'
  | 'dark'
  | 'light'
  | 'amber'
  | 'emptyCredentials'
  | 'wrongCredentials'
  | 'noAccess'
  | 'backendError';

@Component({
  selector: 'app-login',
  templateUrl: './login.component.html',
  styleUrl: './login.component.css'
})
export class LoginComponent {
  readonly languages: { key: Language; label: string }[] = [
    { key: 'ru', label: 'RU' },
    { key: 'tm', label: 'TM' },
    { key: 'en', label: 'EN' }
  ];

  readonly themes: { key: ThemeName; labelKey: LoginTranslationKey }[] = [
    { key: 'dark', labelKey: 'dark' },
    { key: 'light', labelKey: 'light' },
    { key: 'amber', labelKey: 'amber' }
  ];

  readonly translations: Record<Language, Record<LoginTranslationKey, string>> = {
    ru: {
      admin: 'Админка Library',
      welcome: 'Вход в панель',
      subtitle: 'Управление книгами, пользователями и контентом',
      login: 'Email или имя пользователя',
      loginPlaceholder: 'admin или admin@library.local',
      password: 'Пароль',
      passwordPlaceholder: 'Введите пароль',
      button: 'Войти',
      checking: 'Проверка...',
      language: 'Язык',
      theme: 'Тема',
      dark: 'Темная',
      light: 'Светлая',
      amber: 'Книжная',
      emptyCredentials: 'Введите логин и пароль',
      wrongCredentials: 'Неверный логин или пароль',
      noAccess: 'У этого пользователя нет доступа к админке',
      backendError: 'Backend недоступен или вернул ошибку'
    },
    tm: {
      admin: 'Library admin',
      welcome: 'Panele giris',
      subtitle: 'Kitaplary, ulanyjylary we mazmuny dolandyrmak',
      login: 'Email ya-da ulanyjy ady',
      loginPlaceholder: 'admin ya-da admin@library.local',
      password: 'Acar soz',
      passwordPlaceholder: 'Acar sozi girizin',
      button: 'Giris',
      checking: 'Barlanyar...',
      language: 'Dil',
      theme: 'Tema',
      dark: 'Gara',
      light: 'Yagty',
      amber: 'Kitap',
      emptyCredentials: 'Login we acar sozi girizin',
      wrongCredentials: 'Login ya-da acar soz nadogry',
      noAccess: 'Bu ulanyjyda admin paneline giris yok',
      backendError: 'Backend elyeterli dal ya-da yalnyslyk gaytardy'
    },
    en: {
      admin: 'Library admin',
      welcome: 'Sign in',
      subtitle: 'Manage books, users, and content',
      login: 'Email or username',
      loginPlaceholder: 'admin or admin@library.local',
      password: 'Password',
      passwordPlaceholder: 'Enter password',
      button: 'Login',
      checking: 'Checking...',
      language: 'Language',
      theme: 'Theme',
      dark: 'Dark',
      light: 'Light',
      amber: 'Book',
      emptyCredentials: 'Enter login and password',
      wrongCredentials: 'Wrong login or password',
      noAccess: 'This user has no admin access',
      backendError: 'Backend is unavailable or returned an error'
    }
  };

  loginValue = '';
  password = '';
  error = '';
  loading = false;
  language: Language = this.readStoredLanguage();
  theme: ThemeName = this.readStoredTheme();

  constructor(
    private appService: AppService,
    private router: Router
  ) {}

  t(key: LoginTranslationKey): string {
    return this.translations[this.language][key];
  }

  setLanguageValue(language: string): void {
    if (language === 'ru' || language === 'tm' || language === 'en') {
      this.language = language;
      localStorage.setItem('library_admin_language', language);
    }
  }

  setThemeValue(theme: string): void {
    if (theme === 'dark' || theme === 'light' || theme === 'amber') {
      this.theme = theme;
      localStorage.setItem('library_admin_theme', theme);
    }
  }

  submit(): void {
    this.error = '';

    if (!this.loginValue.trim() || !this.password.trim()) {
      this.error = this.t('emptyCredentials');
      return;
    }

    this.loading = true;
    this.appService.login(this.loginValue.trim(), this.password).subscribe({
      next: (response) => {
        this.loading = false;

        if (!response.success || !response.datas) {
          this.error = this.t('wrongCredentials');
          return;
        }

        if (!this.appService.isAdmin(response.datas)) {
          this.error = this.t('noAccess');
          return;
        }

        this.appService.setCurrentUser(response.datas);
        void this.router.navigate(['/admin']);
      },
      error: () => {
        this.loading = false;
        this.error = this.t('backendError');
      }
    });
  }

  private readStoredLanguage(): Language {
    const value = localStorage.getItem('library_admin_language');
    if (value === 'uz') {
      localStorage.setItem('library_admin_language', 'tm');
      return 'tm';
    }
    return value === 'ru' || value === 'tm' || value === 'en' ? value : 'ru';
  }

  private readStoredTheme(): ThemeName {
    const value = localStorage.getItem('library_admin_theme');
    return value === 'dark' || value === 'light' || value === 'amber' ? value : 'dark';
  }
}
