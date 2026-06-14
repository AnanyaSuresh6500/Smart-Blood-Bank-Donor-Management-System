import { Routes, Route, Navigate } from 'react-router-dom';
import { useAuth } from './context/AuthContext';

// Placeholder pages — we'll build these properly on Days 8-9
const Login       = () => <h1>Login Page</h1>;
const AdminDash   = () => <h1>Admin Dashboard</h1>;
const DonorDash   = () => <h1>Donor Dashboard</h1>;
const HospitalDash = () => <h1>Hospital Dashboard</h1>;

// Protects routes — redirects to login if not logged in
const ProtectedRoute = ({ children, role }) => {
  const { user, loading } = useAuth();
  if (loading) return <p>Loading...</p>;
  if (!user) return <Navigate to="/login" />;
  if (role && user.role !== role) return <Navigate to="/login" />;
  return children;
};

function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />

      <Route path="/admin/*" element={
        <ProtectedRoute role="admin"><AdminDash /></ProtectedRoute>
      } />

      <Route path="/donor/*" element={
        <ProtectedRoute role="donor"><DonorDash /></ProtectedRoute>
      } />

      <Route path="/hospital/*" element={
        <ProtectedRoute role="hospital_staff"><HospitalDash /></ProtectedRoute>
      } />

      {/* Default redirect */}
      <Route path="*" element={<Navigate to="/login" />} />
    </Routes>
  );
}

export default App;