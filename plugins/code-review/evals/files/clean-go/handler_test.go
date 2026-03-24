package api

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/example/myapp/internal/store"
)

func TestListItems_DefaultPagination(t *testing.T) {
	s := newTestServer(t)
	s.store.AddItem(store.Item{ID: 1, UserID: 1, Title: "item-1"})
	s.store.AddItem(store.Item{ID: 2, UserID: 1, Title: "item-2"})

	req := httptest.NewRequest("GET", "/items", nil)
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, int64(1)))
	w := httptest.NewRecorder()

	s.ListItems(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp PaginatedResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Total != 2 {
		t.Errorf("expected total=2, got %d", resp.Total)
	}
	if resp.Page != 1 {
		t.Errorf("expected page=1, got %d", resp.Page)
	}
	if resp.PerPage != 20 {
		t.Errorf("expected per_page=20, got %d", resp.PerPage)
	}
}

func TestGetItem_NotFound(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest("GET", "/items/999", nil)
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, int64(1)))
	req.SetPathValue("id", "999")
	w := httptest.NewRecorder()

	s.GetItem(w, req)

	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestGetItem_Unauthorized(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest("GET", "/items/1", nil)
	w := httptest.NewRecorder()

	s.GetItem(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestListItems_InvalidPage(t *testing.T) {
	s := newTestServer(t)

	req := httptest.NewRequest("GET", "/items?page=-1&per_page=0", nil)
	req = req.WithContext(context.WithValue(req.Context(), userIDKey, int64(1)))
	w := httptest.NewRecorder()

	s.ListItems(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp PaginatedResponse
	if err := json.NewDecoder(w.Body).Decode(&resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Page != 1 {
		t.Errorf("expected page clamped to 1, got %d", resp.Page)
	}
	if resp.PerPage != 20 {
		t.Errorf("expected per_page clamped to 20, got %d", resp.PerPage)
	}
}
